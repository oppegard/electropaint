#import "ElectropaintView.h"
#import "EPAdapter.h"
#import "EPClock.h"
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/CAMetalDisplayLink.h>
#include <stdatomic.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <time.h>

@interface EPDisplayRequests : NSObject {
@public
    atomic_bool pending;
}
@end
@implementation EPDisplayRequests
- (instancetype)init {
    self = [super init];
    if (self) atomic_init(&pending, false);
    return self;
}
@end

@interface ElectropaintView () <CAMetalDisplayLinkDelegate>
@end

@implementation ElectropaintView {
    EPState *_engine;
    CAMetalLayer *_metalLayer;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    EPClock _clock;
    BOOL _primed, _running;
    NSUInteger _generation;
    CAMetalDisplayLink *_displayLink API_AVAILABLE(macos(14.0));
    CVDisplayLinkRef _legacyLink;
    NSTimer *_fallbackTimer;
    id _screenObserver;
}

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)preview {
    self = [super initWithFrame:frame isPreview:preview];
    if (!self) return nil;
    self.animationTimeInterval = 1.0 / 60.0;
    _engine = ep_create((uint32_t)time(NULL));
    _device = MTLCreateSystemDefaultDevice();
    if (!_engine || !_device) return nil;
    _queue = [_device newCommandQueue];
    NSString *source = @"#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "struct Vertex { float4 position; float4 color; };\n"
        "struct Output { float4 position [[position]]; float4 color; };\n"
        "vertex Output ep_vertex(uint i [[vertex_id]], const device Vertex *v [[buffer(0)]]) {"
        " return {v[i].position, v[i].color}; }\n"
        "fragment float4 ep_fragment(Output in [[stage_in]]) { return in.color; }\n";
    NSError *error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:source options:nil error:&error];
    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction = [library newFunctionWithName:@"ep_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"ep_fragment"];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _pipeline = [_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!_queue || !_pipeline) {
        NSLog(@"Electropaint Metal initialization failed: %@", error);
        return nil;
    }
    _metalLayer = [CAMetalLayer layer];
    _metalLayer.device = _device;
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly = YES;
    _metalLayer.opaque = YES;
    self.wantsLayer = YES;
    self.layer = _metalLayer;
    [self updateDrawableSize];
    return self;
}

- (void)dealloc {
    [self invalidateDriver];
    if (_screenObserver) [[NSNotificationCenter defaultCenter] removeObserver:_screenObserver];
    ep_destroy(_engine);
}
- (BOOL)hasConfigureSheet { return NO; }
- (NSWindow *)configureSheet { return nil; }
- (BOOL)isOpaque { return YES; }
- (void)updateDrawableSize {
    CGFloat scale = self.window.backingScaleFactor;
    if (scale <= 0) scale = 1;
    _metalLayer.contentsScale = scale;
    _metalLayer.drawableSize = CGSizeMake(MAX(1, self.bounds.size.width * scale),
                                          MAX(1, self.bounds.size.height * scale));
}
- (void)layout { [super layout]; [self updateDrawableSize]; }
- (void)viewDidChangeBackingProperties { [super viewDidChangeBackingProperties]; [self updateDrawableSize]; }
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self updateDrawableSize];
    if (_screenObserver) [[NSNotificationCenter defaultCenter] removeObserver:_screenObserver];
    _screenObserver = nil;
    if (self.window) {
        __weak ElectropaintView *weakSelf = self;
        _screenObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:NSWindowDidChangeScreenNotification object:self.window
            queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
                (void)notification;
                [weakSelf updateDrawableSize];
                [weakSelf restartDriver];
            }];
    }
    [self restartDriver];
}
- (void)invalidateDriver {
    ++_generation;
    if (@available(macOS 14.0, *)) { [_displayLink invalidate]; _displayLink = nil; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (_legacyLink) { CVDisplayLinkStop(_legacyLink); CVDisplayLinkRelease(_legacyLink); _legacyLink = NULL; }
#pragma clang diagnostic pop
    [_fallbackTimer invalidate]; _fallbackTimer = nil;
}
- (void)restartDriver {
    ep_clock_pause(&_clock);
    if (@available(macOS 14.0, *)) {
        if (self.window.screen && _displayLink) {
            float maximum = MAX(1, self.window.screen.maximumFramesPerSecond);
            _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(MIN(60, maximum), maximum, maximum);
            _displayLink.paused = !_running;
            return;
        }
    }
    [self invalidateDriver];
    if (!_running) return;
    if (@available(macOS 14.0, *)) {
        if (self.window.screen) {
            _displayLink = [[CAMetalDisplayLink alloc] initWithMetalLayer:_metalLayer];
            _displayLink.delegate = self;
            float maximum = MAX(1, self.window.screen.maximumFramesPerSecond);
            _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(MIN(60, maximum), maximum, maximum);
            _displayLink.paused = NO;
            [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
            return;
        }
    }
    __weak ElectropaintView *weakSelf = self;
    NSUInteger generation = _generation;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSNumber *screenID = self.window.screen.deviceDescription[@"NSScreenNumber"];
    if (screenID && CVDisplayLinkCreateWithCGDisplay(screenID.unsignedIntValue, &_legacyLink) == kCVReturnSuccess) {
        EPDisplayRequests *requests = [EPDisplayRequests new];
        CVReturn configured = CVDisplayLinkSetOutputHandler(_legacyLink, ^CVReturn(CVDisplayLinkRef link,
            const CVTimeStamp *now, const CVTimeStamp *output, CVOptionFlags flags, CVOptionFlags *outFlags) {
            (void)link; (void)now; (void)flags; (void)outFlags;
            if (atomic_exchange(&requests->pending, true)) return kCVReturnSuccess;
            double timestamp = (output->flags & kCVTimeStampHostTimeValid)
                ? (double)output->hostTime / CVGetHostClockFrequency() : CACurrentMediaTime();
            dispatch_async(dispatch_get_main_queue(), ^{
                ElectropaintView *view = weakSelf;
                if (view && view->_running && view->_generation == generation)
                    [view renderAtTimestamp:timestamp drawable:nil];
                atomic_store(&requests->pending, false);
            });
            return kCVReturnSuccess;
        });
        if (configured == kCVReturnSuccess && CVDisplayLinkStart(_legacyLink) == kCVReturnSuccess) return;
        CVDisplayLinkRelease(_legacyLink); _legacyLink = NULL;
    }
#pragma clang diagnostic pop
    _fallbackTimer = [NSTimer timerWithTimeInterval:1.0/60.0 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        [weakSelf renderAtTimestamp:CACurrentMediaTime() drawable:nil];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_fallbackTimer forMode:NSRunLoopCommonModes];
}
- (void)startAnimation {
    if (_running) return;
    _running = YES;
    [super startAnimation];
    [self restartDriver];
}
- (void)stopAnimation {
    _running = NO;
    if (@available(macOS 14.0, *)) {
        if (_displayLink) _displayLink.paused = YES;
        else [self invalidateDriver];
    } else [self invalidateDriver];
    ep_clock_pause(&_clock);
    [super stopAnimation];
}
- (void)metalDisplayLink:(CAMetalDisplayLink *)link needsUpdate:(CAMetalDisplayLinkUpdate *)update
    API_AVAILABLE(macos(14.0)) {
    if (_running && link == _displayLink)
        [self renderAtTimestamp:update.targetPresentationTimestamp drawable:update.drawable];
}
- (void)animateOneFrame {
    // ScreenSaver hosts may still call this while the display link owns drawing.
    if (!_running || _legacyLink || _fallbackTimer) return;
    if (@available(macOS 14.0, *)) { if (_displayLink) return; }
    [self renderAtTimestamp:CACurrentMediaTime() drawable:nil];
}
- (void)renderAtTimestamp:(CFTimeInterval)timestamp drawable:(id<CAMetalDrawable>)drawable {
    if (!_running || !_pipeline || self.bounds.size.width <= 0 || self.bounds.size.height <= 0) return;
    int width = (int)_metalLayer.drawableSize.width, height = (int)_metalLayer.drawableSize.height;
    if (!_primed) { ep_step(_engine, width, height); _primed = YES; }
    EPClockUpdate update = ep_clock_advance(&_clock, timestamp);
    for (unsigned i=0; i<update.steps; ++i) ep_step(_engine, width, height);
    const EPFrame *frame = ep_render(_engine, width, height, update.fraction);
    BOOL displayLinkDrawable = drawable != nil;
    if (!drawable) drawable = [_metalLayer nextDrawable];
    if (!drawable) return;
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLCommandBuffer> command = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:_pipeline];
    [encoder setCullMode:MTLCullModeNone];
    if (frame->vertexCount) {
        id<MTLBuffer> buffer = [_device newBufferWithBytes:frame->vertices
            length:frame->vertexCount * sizeof(EPVertex) options:MTLResourceStorageModeShared];
        [encoder setVertexBuffer:buffer offset:0 atIndex:0];
        for (unsigned i = 0; i < frame->batchCount; ++i) {
            EPBatch batch = frame->batches[i];
            [encoder drawPrimitives:batch.lines ? MTLPrimitiveTypeLine : MTLPrimitiveTypeTriangle
                       vertexStart:batch.first vertexCount:batch.count];
        }
    }
    [encoder endEncoding];
    if (!displayLinkDrawable) [command presentDrawable:drawable];
    [command commit];
    // Metal display links require immediate presentation before their deadline.
    if (displayLinkDrawable) [drawable present];
}
@end
