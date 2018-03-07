//
//  ViewController.m
//  LearnOpenGLESWithGPUImage
//
//  Created by loyinglin on 16/5/10.
//  Copyright © 2016年 loyinglin. All rights reserved.
//

#import "LYOpenGLView.h"
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVUtilities.h>
#import <mach/mach_time.h>
#import <GLKit/GLKit.h>
#import "Plane.h"
#import "GLBox.h"
// Uniform index.

typedef struct {
    GLKVector3 position;
    GLKVector3 color;
    GLfloat indensity;
    GLfloat ambientIndensity;
}PointLight;

typedef struct {
    GLKVector3 diffuseColor;
    GLKVector3 ambientColor;
    GLKVector3 specularColor;
    GLfloat smoothness;
}Material;


enum
{
	UNIFORM_Y,
	UNIFORM_UV,
	UNIFORM_COLOR_CONVERSION_MATRIX,
    UNIFORM_RGBA,
	NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];
// Color Conversion Constants (YUV to RGB) including adjustment from 16-235/16-240 (video range)

// BT.601, which is the standard for SDTV.
static const GLfloat kColorConversion601[] = {
		1.164,  1.164, 1.164,
		  0.0, -0.392, 2.017,
		1.596, -0.813,   0.0,
};

// BT.709, which is the standard for HDTV.
static const GLfloat kColorConversion709[] = {
		1.164,  1.164, 1.164,
		  0.0, -0.213, 2.112,
		1.793, -0.533,   0.0,
};

// BT.601 full range (ref: http://www.equasys.de/colorconversion.html)
const GLfloat kColorConversion601FullRange[] = {
    1.0,    1.0,    1.0,
    0.0,    -0.343, 1.765,
    1.4,    -0.711, 0.0,
};



@interface LYOpenGLView ()
{
	// The pixel dimensions of the CAEAGLLayer.
	GLint _backingWidth;
	GLint _backingHeight;

	EAGLContext *_context;
	CVOpenGLESTextureRef _lumaTexture;
	CVOpenGLESTextureRef _chromaTexture;
    CVOpenGLESTextureRef _rgbaTexture;
	CVOpenGLESTextureCacheRef _videoTextureCache;
	
	GLuint _frameBufferHandle;
	GLuint _colorBufferHandle;
	
    GLfloat *_preferredConversion;
    
    GLuint _textrueY;
    GLuint _textureUV;
    GLKMatrix3 _matrix3;
}

@property GLuint program;
@property GLuint rgbaProgram;
@property (nonatomic, strong) Plane *previewPlane;
@property (nonatomic, strong) GLBox *box;
@property (nonatomic, assign) GLKMatrix4 projectionMatrix;
@property (nonatomic, assign) GLKMatrix4 cameraMatrix;
@property (nonatomic, assign) PointLight light;
@property (nonatomic, assign) Material material;
@property (nonatomic, assign) GLKVector3 eyePosition;
@property (nonatomic, assign) CGSize frameBufferSize;
@property (nonatomic, assign) GLKMatrix4 planeProjectionMatrix;

@property (nonatomic, strong) NSMutableArray <GLObject *> * objects;
@property (nonatomic, assign) BOOL useNormalMap;


- (void)setupBuffers;
- (void)cleanUpTextures;

- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;

@end

@implementation LYOpenGLView

+ (Class)layerClass
{
	return [CAEAGLLayer class];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	if ((self = [super initWithCoder:aDecoder]))
	{
		self.contentScaleFactor = [[UIScreen mainScreen] scale];

		CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;

		eaglLayer.opaque = TRUE;
		eaglLayer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking :[NSNumber numberWithBool:NO],
										  kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8};

		_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

		if (!_context || ![EAGLContext setCurrentContext:_context]) {
			return nil;
		}
		
		_preferredConversion = kColorConversion709;
	}
	return self;
}

- (void)createPlaneTexture:(GLuint)textureY textureUV:(GLuint)textureUV matrix3:(GLfloat *)matrix3
{
    [EAGLContext setCurrentContext:_context];
    
    NSString *vertexStr = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
    NSString *fragmentStr = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
    
    GLContext *planeContext = [GLContext contextWithVertexShaderPath:vertexStr fragmentShaderPath:fragmentStr];
    
    self.previewPlane = [[Plane alloc] initWithGLContext:planeContext textureY:textureY textureUV:textureUV matrix:matrix3];
}

# pragma mark - OpenGL setup
- (void)setupGL
{
	[EAGLContext setCurrentContext:_context];
	[self setupBuffers];
	
	// Create CVOpenGLESTextureCacheRef for optimal CVPixelBufferRef to GLES texture conversion.
	if (!_videoTextureCache) {
		CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
		if (err != noErr) {
			NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
			return;
		}
	}
}

- (void)createBox
{
    // 使用透视投影矩阵
    float aspect = self.frame.size.width / self.frame.size.height;
    self.projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(90), aspect, 0.1, 500.0);
    
    self.cameraMatrix = GLKMatrix4MakeLookAt(0, 1, 6.5, 0, 0, 0, 0, 1, 0);
    
    PointLight defaultLight;
    defaultLight.color = GLKVector3Make(1, 1, 1); // 白色的灯
    defaultLight.position = GLKVector3Make(30, 100, 0);
    defaultLight.indensity = 1.0;
    defaultLight.ambientIndensity = 0.1;
    self.light = defaultLight;
    
    Material material;
    material.ambientColor = GLKVector3Make(1, 1, 1);
    material.diffuseColor = GLKVector3Make(0.1, 0.1, 0.1);
    material.specularColor = GLKVector3Make(1, 1, 1);
    material.smoothness = 70;
    self.material = material;
    
    self.useNormalMap = YES;
    UIImage *normalImage = [UIImage imageNamed:@"normal.png"];
    GLKTextureInfo *normalMap = [GLKTextureLoader textureWithCGImage:normalImage.CGImage options:nil error:nil];
    UIImage *diffuseImage = [UIImage imageNamed:@"texture.jpg"];
    GLKTextureInfo *diffuseMap = [GLKTextureLoader textureWithCGImage:diffuseImage.CGImage options:nil error:nil];
    
    NSString *objFilePath = [[NSBundle mainBundle] pathForResource:@"cube" ofType:@"obj"];
    
    NSString *vertexShaderPath = [[NSBundle mainBundle] pathForResource:@"vertex2" ofType:@".glsl"];
    NSString *fragmentShaderPath = [[NSBundle mainBundle] pathForResource:@"fragment2" ofType:@".glsl"];
    
   GLContext *boxContext = [GLContext contextWithVertexShaderPath:vertexShaderPath fragmentShaderPath:fragmentShaderPath];
    
    self.box = [GLBox objWithGLContext:boxContext objFile:objFilePath diffuseMap:diffuseMap normalMap:normalMap];
    self.box.modelMatrix = GLKMatrix4MakeRotation(- M_PI / 2.0, 0, 1, 0);
}

#pragma mark - Utilities

- (void)setupBuffers
{
	glEnable(GL_DEPTH_TEST);
	
	glGenFramebuffers(1, &_frameBufferHandle);
	glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
	
	glGenRenderbuffers(1, &_colorBufferHandle);
	glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
	
	[_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);

	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorBufferHandle);
    
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
		NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
	}
}

- (void)cleanUpTextures
{
	if (_lumaTexture) {
		CFRelease(_lumaTexture);
		_lumaTexture = NULL;
	}
	
	if (_chromaTexture) {
		CFRelease(_chromaTexture);
		_chromaTexture = NULL;
	}
	
	// Periodic texture cache flush every frame
	CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
}

- (void)dealloc
{
	[self cleanUpTextures];
	
	if(_videoTextureCache) {
		CFRelease(_videoTextureCache);
	}
}

#pragma mark - OpenGLES drawing

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer
           rbgaPixelBuffer:(CVPixelBufferRef)rgbaPixel
                     array:(NSArray *)points
{
	CVReturn err;
    
    if ([EAGLContext currentContext] != _context) {
        [EAGLContext setCurrentContext:_context]; // 非常重要的一行代码
    }
    
    [self cleanUpTextures];
    
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    
    // Set the view port to the entire view.
    glViewport(0, 0, _backingWidth, _backingHeight);
    
    glClearColor(0.1f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
	if (pixelBuffer != NULL) {
		int frameWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
		int frameHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
		
		if (!_videoTextureCache) {
			NSLog(@"No video texture cache");
			return;
		}
		
		/*
		 Use the color attachment of the pixel buffer to determine the appropriate color conversion matrix.
		 */
		CFTypeRef colorAttachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
		
		if (colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
            if (self.isFullYUVRange) {
                _preferredConversion = kColorConversion601FullRange;
            }
            else {
                _preferredConversion = kColorConversion601;
            }
		}
		else {
			_preferredConversion = kColorConversion709;
		}
		
		/*
         CVOpenGLESTextureCacheCreateTextureFromImage will create GLES texture optimally from CVPixelBufferRef.
         */
		
		/*
         Create Y and UV textures from the pixel buffer. These textures will be drawn on the frame buffer Y-plane.
         */
		glActiveTexture(GL_TEXTURE0);
		err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
														   _videoTextureCache,
														   pixelBuffer,
														   NULL,
														   GL_TEXTURE_2D,
														   GL_LUMINANCE,
														   frameWidth,
														   frameHeight,
														   GL_LUMINANCE,
														   GL_UNSIGNED_BYTE,
														   0,
														   &_lumaTexture);
		if (err) {
			NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
		}
		
        glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		
		// UV-plane.
		glActiveTexture(GL_TEXTURE1);
		err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
														   _videoTextureCache,
														   pixelBuffer,
														   NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_LUMINANCE_ALPHA,
                                                           frameWidth / 2,
                                                           frameHeight / 2,
                                                           GL_LUMINANCE_ALPHA,
														   GL_UNSIGNED_BYTE,
														   1,
														   &_chromaTexture);
		if (err) {
			NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
		}
		
		glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	}
    
    if (rgbaPixel != NULL) {
        
        int frameWidth = (int)CVPixelBufferGetWidth(rgbaPixel);
        int frameHeight = (int)CVPixelBufferGetHeight(rgbaPixel);
        
        if (!_videoTextureCache) {
            NSLog(@"No video texture cache");
            return;
        }
        
        glActiveTexture(GL_TEXTURE2);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           rgbaPixel,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_LUMINANCE,
                                                           frameWidth,
                                                           frameHeight,
                                                           GL_LUMINANCE,
                                                           GL_UNSIGNED_BYTE,
                                                           0,
                                                           &_rgbaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        glBindTexture(CVOpenGLESTextureGetTarget(_rgbaTexture), CVOpenGLESTextureGetName(_rgbaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    
    [self drawPreviewPlane];
    
    [self drawBox];

	glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    
    if ([EAGLContext currentContext] == _context) {
        [_context presentRenderbuffer:GL_RENDERBUFFER];
    }
}

- (void)drawPreviewPlane
{
    if (!_previewPlane) {
        
        [self createPlaneTexture:CVOpenGLESTextureGetName(_lumaTexture) textureUV:CVOpenGLESTextureGetName(_chromaTexture) matrix3:_preferredConversion];
    }
    
    [_previewPlane.context active];
    
    [_previewPlane draw:_previewPlane.context];
}
- (void)drawBox
{
    if (!_box) {
        
        [self createBox];
    }
    static float elapsedTime = 0.0;
    elapsedTime += 0.1;
    self.eyePosition = GLKVector3Make(0, 2, 6);
    GLKVector3 lookAtPosition = GLKVector3Make(0, 0, 0);
    self.cameraMatrix = GLKMatrix4MakeLookAt(self.eyePosition.x, self.eyePosition.y, self.eyePosition.z, lookAtPosition.x, lookAtPosition.y, lookAtPosition.z, 0, 1, 0);
    self.box.modelMatrix = GLKMatrix4MakeRotation(- M_PI / 2.0 * elapsedTime / 4.0, 1, 1, 1);
    [self.box.context active];
    [self.box.context setUniform1f:@"elapsedTime" value:(GLfloat)elapsedTime];
    [self.box.context setUniformMatrix4fv:@"projectionMatrix" value:self.projectionMatrix];
    [self.box.context setUniformMatrix4fv:@"cameraMatrix" value:self.cameraMatrix];
    [self.box.context setUniform3fv:@"eyePosition" value:self.eyePosition];
    [self.box.context setUniform3fv:@"light.position" value:self.light.position];
    [self.box.context setUniform3fv:@"light.color" value:self.light.color];
    [self.box.context setUniform1f:@"light.indensity" value:self.light.indensity];
    [self.box.context setUniform1f:@"light.ambientIndensity" value:self.light.ambientIndensity];
    [self.box.context setUniform3fv:@"material.diffuseColor" value:self.material.diffuseColor];
    [self.box.context setUniform3fv:@"material.ambientColor" value:self.material.ambientColor];
    [self.box.context setUniform3fv:@"material.specularColor" value:self.material.specularColor];
    [self.box.context setUniform1f:@"material.smoothness" value:self.material.smoothness];
    [self.box.context setUniform1i:@"useNormalMap" value:self.useNormalMap];
    [self.box draw:self.box.context];
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

@end

