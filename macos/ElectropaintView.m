#import "ElectropaintView.h"
#import "EPAdapter.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <CoreGraphics/CoreGraphics.h>
#include <time.h>

@implementation ElectropaintView {
    EPState *_engine;
    CAMetalLayer *_metalLayer;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    CFTimeInterval _lastTime, _accumulator;
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
    _metalLayer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
    self.wantsLayer = YES;
    self.layer = _metalLayer;
    [self updateDrawableSize];
    return self;
}

- (void)dealloc { ep_destroy(_engine); }
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
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self updateDrawableSize]; }
- (void)startAnimation {
    _lastTime = 0;
    _accumulator = 0;
    [super startAnimation];
}
- (void)stopAnimation {
    [super stopAnimation];
    _lastTime = 0;
    _accumulator = 0;
}
- (BOOL)shouldAnimateOnCurrentDisplay {
    if (self.isPreview) return YES;
    NSNumber *display = self.window.screen.deviceDescription[@"NSScreenNumber"];
    return display != nil && display.unsignedIntValue == CGMainDisplayID();
}
- (void)animateOneFrame {
    if (!_pipeline || self.bounds.size.width <= 0 || self.bounds.size.height <= 0) return;
    if (![self shouldAnimateOnCurrentDisplay]) {
        _lastTime = 0;
        _accumulator = 0;
        [self renderFrame:NULL];
        return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    _accumulator += _lastTime == 0 ? 1.0 / 60.0 : MIN(MAX(0, now - _lastTime), 8.0 / 60.0);
    _lastTime = now;
    const EPFrame *frame = NULL;
    while (_accumulator + 1e-9 >= 1.0 / 60.0) {
        frame = ep_step(_engine, (int)_metalLayer.drawableSize.width, (int)_metalLayer.drawableSize.height);
        _accumulator -= 1.0 / 60.0;
    }
    if (!frame) return;
    [self renderFrame:frame];
}
- (void)renderFrame:(const EPFrame *)frame {
    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
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
    if (frame && frame->vertexCount) {
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
    [command presentDrawable:drawable];
    [command commit];
}
@end
