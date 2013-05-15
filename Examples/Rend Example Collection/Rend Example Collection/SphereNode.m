//
//  SphereNode.m
//  dgi12Projekt
//
//  Created by Anton Holmberg on 2012-05-25.
//  Copyright (c) 2012 Anton Holmberg. All rights reserved.
//

#import "SphereNode.h"
#import <AVFoundation/AVFoundation.h>

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

@interface SphereNode ()

- (CC3Vector)positionForHorizontalAngle:(float)ha topAngle:(float)ta radius:(float)r;
- (CC3Vector)bumpAxisXForHorizontalAngle:(float)ha topAngle:(float)ta;
- (CC3Vector)bumpAxisYForHorizontalAngle:(float)ha topAngle:(float)ta;

@property (nonatomic, assign) CVOpenGLESTextureRef lumaTexture;
@property (nonatomic, assign) CVOpenGLESTextureRef chromaTexture;
@property (nonatomic, assign) CVOpenGLESTextureCacheRef videoTextureCache;

@property (nonatomic, assign) const GLfloat *preferredConversion;

@end

@implementation SphereNode

@synthesize texture = texture_;
@synthesize bumpMap = bumpMap_;
@synthesize shinyness = shinyness_;
@synthesize specularLightBrightness = specularLightBrightness_;
@synthesize bumpMapOffset = bumpMapOffset_;

- (id)initWithResolutionX:(int)resolutionX resolutionY:(int)resolutionY radius:(float)radius {
    if (self = [super init]) {
        
        resolutionX_ = resolutionX;
        resolutionY_ = resolutionY;
        
        float r = radius;
        
        nAttribs_ = 2 * resolutionX_ * (resolutionY_ - 1);
        
        NSLog(@"nAttribs_: %d", nAttribs_);
        attribs_ = calloc(nAttribs_, sizeof(SphereNodeAttribs));
        memset(attribs_, 0, nAttribs_ * sizeof(SphereNodeAttribs));
        for(int iy = 0; iy < resolutionY_ - 1; iy++) {
            for(int ix = 0; ix < resolutionX_; ix++) {
                
                int index = iy * 2 * resolutionX_ + 2 * ix;
                
                float fx = ix/(float)(resolutionX_ - 1);
                
                float fy = iy/(float)(resolutionY_ - 1);
                float nextFY = (iy + 1)/(float)(resolutionY_ - 1);
                
                float ha = fx * 2 * M_PI;
                float ta0 = fy * M_PI;
                float ta1 = nextFY * M_PI;
                
                attribs_[index].position = [self positionForHorizontalAngle:ha topAngle:ta0 radius:r];
                attribs_[index].texCoord = CC3VectorMake(fx, fy, 0);
                attribs_[index].bumpAxisX = [self bumpAxisXForHorizontalAngle:ha topAngle:ta0];
                attribs_[index].bumpAxisY = [self bumpAxisYForHorizontalAngle:ha topAngle:ta0];
                
                attribs_[index+1].position = [self positionForHorizontalAngle:ha topAngle:ta1 radius:r];
                attribs_[index+1].texCoord = CC3VectorMake(fx, nextFY, 0);
                attribs_[index+1].bumpAxisX = [self bumpAxisXForHorizontalAngle:ha topAngle:ta1];
                attribs_[index+1].bumpAxisY = [self bumpAxisYForHorizontalAngle:ha topAngle:ta1];
            }
        }
    }
    return self;
}

- (void)setPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!_videoTextureCache) {
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, [EAGLContext currentContext], NULL, &_videoTextureCache);
        if (err != noErr) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        }
    }
    
    if (_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
    }
    
    _pixelBuffer = pixelBuffer;
    
    if (_pixelBuffer) {
        CVPixelBufferRetain(_pixelBuffer);
    }
    
    CVReturn err;
    if (pixelBuffer != NULL) {
        int frameWidth = CVPixelBufferGetWidth(pixelBuffer);
        int frameHeight = CVPixelBufferGetHeight(pixelBuffer);
        
        if (!_videoTextureCache) {
            NSLog(@"No video texture cache");
            return;
        }
        
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
        
        
        /*
         Use the color attachment of the pixel buffer to determine the appropriate color conversion matrix.
         */
        CFTypeRef colorAttachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
        
        if (colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
            _preferredConversion = kColorConversion601;
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
        //glActiveTexture(GL_TEXTURE0);
        
        [[REGLStateManager sharedManager] setActiveTexture:GL_TEXTURE0];
        
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RED_EXT,
                                                           frameWidth,
                                                           frameHeight,
                                                           GL_RED_EXT,
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
        [[REGLStateManager sharedManager] setActiveTexture:GL_TEXTURE1];
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RG_EXT,
                                                           frameWidth / 2,
                                                           frameHeight / 2,
                                                           GL_RG_EXT,
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
        
        //glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
        
        // Set the view port to the entire view.
        //glViewport(0, 0, _backingWidth, _backingHeight);
        
        //CFRelease(pixelBuffer);
    }
}


- (CC3Vector)bumpAxisXForHorizontalAngle:(float)ha topAngle:(float)ta {
    if(ta == 0) ta = 0.001;
    if(ABS(ta - M_PI) < 0.001) ta = M_PI - 0.001;
    CC3Vector axis = CC3VectorNormalize(CC3VectorDifference([self positionForHorizontalAngle:ha + 0.001 topAngle:ta radius:10],
                                                            [self positionForHorizontalAngle:ha - 0.001 topAngle:ta radius:10]));
    return axis;
}


- (CC3Vector)bumpAxisYForHorizontalAngle:(float)ha topAngle:(float)ta {
    if(ta == 0) ta = 0.001;
    if(ABS(ta - M_PI) < 0.001) ta = M_PI - 0.001;
    CC3Vector axis = CC3VectorNormalize(CC3VectorDifference([self positionForHorizontalAngle:ha topAngle:ta + 0.001 radius:10],
                                                            [self positionForHorizontalAngle:ha topAngle:ta - 0.001 radius:10]));
    return axis;
}


- (CC3Vector)positionForHorizontalAngle:(float)ha topAngle:(float)ta radius:(float)r {
    return CC3VectorMake(r * sin(ta) * cos(ha), r * cos(ta), r * sin(ta) * sin(ha));
}

- (void)dealloc {
    free(attribs_);
    
    self.texture = nil;
    self.bumpMap = nil;
    
    [super dealloc];
}

+ (REProgram*)program {
    return [REProgram programWithVertexFilename:@"sBumpSphere.vsh" fragmentFilename:@"sBumpSphere.fsh"];
}

- (void)draw {
    
    if (!_preferredConversion) {
        return;
    }
    
    [super draw];
    
    
    
    GLint a_position = [self.program attribLocation:@"a_position"];
    GLint a_texCoord = [self.program attribLocation:@"a_texCoord"];
    GLint a_bumpAxisX = [self.program attribLocation:@"a_bumpAxisX"];
    GLint a_bumpAxisY = [self.program attribLocation:@"a_bumpAxisY"];
    
    
    // Use shader program.
    GLint u_colorConversionMatrix = [self.program uniformLocation:@"u_colorConversionMatrix"];
    GLint s_textureY = [self.program uniformLocation:@"s_textureY"];
    GLint s_textureUV = [self.program uniformLocation:@"s_textureUV"];
    
    glUniformMatrix3fv(u_colorConversionMatrix, 1, GL_FALSE, _preferredConversion);
    
    glUniform1i(s_textureY, 0);
	glUniform1i(s_textureUV, 1);
    
    
    [[REGLStateManager sharedManager] setActiveTexture:GL_TEXTURE0];
    glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
    
    [[REGLStateManager sharedManager] setActiveTexture:GL_TEXTURE1];
    glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
    
    
    
    /*
    glUniform1i([self.program uniformLocation:@"s_texture"], 0);
    [texture_ bind:GL_TEXTURE0];
    glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
    
    glUniform1i([self.program uniformLocation:@"s_bumpMap"], 1);
    [bumpMap_ bind:GL_TEXTURE1];
     */
     
    
    glUniform1f([self.program uniformLocation:@"u_shinyness"], shinyness_);
    glUniform1f([self.program uniformLocation:@"u_specularLightBrightness"], specularLightBrightness_);
    glUniform1f([self.program uniformLocation:@"u_bumpMapOffset"], bumpMapOffset_);
    
    glEnableVertexAttribArray(a_position);
    glEnableVertexAttribArray(a_texCoord);
    glEnableVertexAttribArray(a_bumpAxisX);
    glEnableVertexAttribArray(a_bumpAxisY);
    
    glVertexAttribPointer(a_position, 3, GL_FLOAT, GL_FALSE, sizeof(SphereNodeAttribs), (void*)(attribs_) + offsetof(SphereNodeAttribs, position));
    glVertexAttribPointer(a_texCoord, 3, GL_FLOAT, GL_FALSE, sizeof(SphereNodeAttribs), (void*)(attribs_) + offsetof(SphereNodeAttribs, texCoord));
    glVertexAttribPointer(a_bumpAxisX, 3, GL_FLOAT, GL_FALSE, sizeof(SphereNodeAttribs), (void*)(attribs_) + offsetof(SphereNodeAttribs, bumpAxisX));
    glVertexAttribPointer(a_bumpAxisY, 3, GL_FLOAT, GL_FALSE, sizeof(SphereNodeAttribs), (void*)(attribs_) + offsetof(SphereNodeAttribs, bumpAxisY));
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, nAttribs_);
}

@end
