//
//  DDWeChatHandler.m
//  DDSocialDemo
//
//  Created by lilingang on 16/1/4.
//  Copyright © 2016年 LiLingang. All rights reserved.
//

#import "DDWeChatHandler.h"
#import "WXApi.h"

#import "DDSocialShareContentProtocol.h"

#import "UIImage+Zoom.h"

const CGFloat DDWeChatThumbnailDataMaxSize = 32 * 1024.0;
const CGFloat DDWeChatImageDataMaxSize = 10 * 1024.0 * 1024.0;

@interface DDWeChatHandler ()<WXApiDelegate>

/*授权*/
@property (nonatomic, assign) DDSSAuthMode authMode;
@property (nonatomic, copy) DDSSAuthEventHandler authEventHandler;

/*分享*/
@property (nonatomic, assign) DDSSScene shareScene;
@property (nonatomic, copy) DDSSShareEventHandler shareEventHandler;

@end

@implementation DDWeChatHandler

#pragma mark - Public Methods

#pragma mark -判断微信客户端是否安装
+ (BOOL)isWeChatInstalled{
    return [WXApi isWXAppInstalled];
}

#pragma mark -向微信终端程序注册第三方应用
- (BOOL)registerApp:(NSString *)appid withDescription:(NSString *)appDescription{
    return [WXApi registerApp:appid withDescription:appDescription];
}

#pragma mark -处理微信通过URL启动App时传递的数据
- (BOOL)handleOpenURL:(NSURL *)url{
    return [WXApi handleOpenURL:url delegate:self];
}


#pragma mark -微信授权逻辑
- (BOOL)authWithMode:(DDSSAuthMode)mode
          controller:(UIViewController *)viewController
             handler:(DDSSAuthEventHandler)handler{
    self.authMode = mode;
    self.authEventHandler = handler;
    
    if (self.authEventHandler) {
        self.authEventHandler(DDSSPlatformWeChat,DDSSAuthStateBegan, nil, nil);
    }
    
    SendAuthReq* authReq =[[SendAuthReq alloc ] init ];
    authReq.scope = @"snsapi_userinfo" ;
    authReq.state = @"1990" ;
    return [WXApi sendAuthReq:authReq viewController:viewController delegate:self];
}

#pragma mark -微信分享
- (BOOL)shareWithProtocol:(id<DDSocialShareContentProtocol>)protocol
               shareScene:(DDSSScene)shareScene
              contentType:(DDSSContentType)contentType
                  handler:(DDSSShareEventHandler)handler{
    self.shareScene = shareScene;
    self.shareEventHandler = handler;
    
    if (self.shareEventHandler) {
        self.shareEventHandler(DDSSPlatformWeChat, self.shareScene, DDSSShareStateBegan, nil);
    }
    if (contentType == DDSSContentTypeText && [protocol conformsToProtocol:@protocol(DDSocialShareTextProtocol)]) {
        return [self shareTextWithProtocol:(id<DDSocialShareTextProtocol>)protocol];
    } else if (contentType == DDSSContentTypeImage && [protocol conformsToProtocol:@protocol(DDSocialShareImageProtocol)]){
        return [self shareImageWithProtocol:(id<DDSocialShareImageProtocol>)protocol];
    } else if (contentType == DDSSContentTypeWebPage && [protocol conformsToProtocol:@protocol(DDSocialShareWebPageProtocol)]){
        return [self shareWebPageWithProtocol:(id<DDSocialShareWebPageProtocol>)protocol];
    } else {
        if (self.shareEventHandler) {
            NSString *errorDescription = [NSString stringWithFormat:@"share format error:%@ shareType:%lu",NSStringFromClass([protocol class]),(unsigned long)contentType];
            NSError *error = [NSError errorWithDomain:@"WeChat Local Share Error" code:-1 userInfo:@{NSLocalizedDescriptionKey:errorDescription}];
            self.shareEventHandler(DDSSPlatformWeChat, self.shareScene, DDSSShareStateFail, error);
            self.shareEventHandler = nil;
        }
        return NO;
    }
}

#pragma mark -第三方通知微信，打开指定微信号profile页面
- (BOOL)JumpToBizProfileWithExtMsg:(NSString *)extMsg username:(NSString *)userName profileType:(int)profileType{
    JumpToBizProfileReq *bizProfile = [[JumpToBizProfileReq alloc]init];
    bizProfile.extMsg = extMsg;
    bizProfile.profileType = profileType;
    bizProfile.username = userName;
    BOOL ret = [WXApi sendReq:bizProfile];
    if (!ret) {
        NSLog(@"JumpToBizProfileReq failed");
    }
    return ret;
}

#pragma mark - Private Methods

- (BOOL)shareTextWithProtocol:(id<DDSocialShareTextProtocol>)protocol{
    NSString *text = [protocol ddShareText];
    return [self sendWithText:text mediaMessage:nil];
}

- (BOOL)shareImageWithProtocol:(id<DDSocialShareImageProtocol>)protocol{
    WXMediaMessage *mediaMessage = [WXMediaMessage message];
    mediaMessage.title = [protocol ddShareImageWithTitle];
    
    NSData *imageData = [protocol ddShareImageWithImageData];
    //图片
    WXImageObject *ext = [WXImageObject object];
    if ([protocol respondsToSelector:@selector(ddShareImageWithImageURL)]) {
        ext.imageUrl = [protocol ddShareImageWithImageURL];
    } else {
        ext.imageData = [UIImage imageData:imageData maxBytes:DDWeChatImageDataMaxSize];
    }
    mediaMessage.mediaObject = ext;
    
    //缩略图
    NSData *thumbData = imageData;
    if ([protocol respondsToSelector:@selector(ddShareImageWithThumbnailData)]) {
        thumbData = [protocol ddShareImageWithThumbnailData];
    }
    mediaMessage.thumbData = [UIImage imageData:thumbData maxBytes:DDWeChatThumbnailDataMaxSize];
    return [self sendWithText:nil mediaMessage:mediaMessage];
}

- (BOOL)shareWebPageWithProtocol:(id<DDSocialShareWebPageProtocol>)protocol{
    WXMediaMessage *mediaMessage = [WXMediaMessage message];
    mediaMessage.title = [protocol ddShareWebPageWithTitle];
    mediaMessage.description = [protocol ddShareWebPageWithDescription];
    
    NSData *thumbImageData = [protocol ddShareWebPageWithImageData];
    mediaMessage.thumbData = [UIImage imageData:thumbImageData maxBytes:DDWeChatThumbnailDataMaxSize];
    
    WXWebpageObject *ext = [WXWebpageObject object];
    ext.webpageUrl = [protocol ddShareWebPageWithWebpageUrl];
    mediaMessage.mediaObject = ext;
    return [self sendWithText:nil mediaMessage:mediaMessage];
}

- (BOOL)sendWithText:(NSString *)text
        mediaMessage:(WXMediaMessage *)message{
    enum WXScene scene = WXSceneSession;
    if (self.shareScene == DDSSSceneWXSession) {
        scene = WXSceneSession;
    } else if (self.shareScene == DDSSSceneWXTimeline){
        scene = WXSceneTimeline;
    }
    
    SendMessageToWXReq *messageToWXReq = [[SendMessageToWXReq alloc] init];
    messageToWXReq.message = message;
    messageToWXReq.text = text;
    messageToWXReq.bText = text ? YES : NO;
    messageToWXReq.scene = scene;
    BOOL sendSuccess = [WXApi sendReq:messageToWXReq];
    if (!sendSuccess) {
        if (self.shareEventHandler) {
            NSError *error = [NSError errorWithDomain:@"WeChat Local Share Error" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"请检查分享格式是否满足如下条件(如果有内容的话):\n1、文本分享\n(1)文本长度必须大于0且小于10K\n2、多媒体分享\n(1)标题长度不能超过512字节(2)描述内容长度不能超过1K(3)缩略图数据大小不能超过32K(4)图片真实数据内容大小不能超过10M(5)网页的url地址长度不能超过10K"}];
            self.shareEventHandler(DDSSPlatformWeChat, self.shareScene, DDSSShareStateFail, error);
            self.shareEventHandler = nil;
        }
    }
    return sendSuccess;
}


#pragma mark - WXApiDelegate

- (void)onResp:(BaseResp*)resp{
    //登录授权获取到code
    if ([resp isKindOfClass:[SendAuthResp class]]) {
        if (resp.errCode == WXSuccess) {
            if (self.authEventHandler) {
                SendAuthResp *authResp = (SendAuthResp *)resp;
                self.authEventHandler(DDSSPlatformWeChat,DDSSAuthStateSuccess, authResp.code, nil);
            }
        } else if (resp.errCode == WXErrCodeUserCancel){
            if (self.authEventHandler) {
                self.authEventHandler(DDSSPlatformWeChat, DDSSAuthStateCancel, nil, nil);
            }
        } else {
            if (self.authEventHandler) {
                NSError *error = [NSError errorWithDomain:@"WeChat Auth Error" code:resp.errCode userInfo:@{NSLocalizedDescriptionKey:resp.errStr}];
                self.authEventHandler(DDSSPlatformWeChat, DDSSAuthStateFail, nil, error);
            }
        }
        self.authEventHandler = nil;
    }
    
    //分享
    if ([resp isKindOfClass:[SendMessageToWXResp class]]) {
        if (resp.errCode == WXSuccess) {
            if (self.shareEventHandler) {
                self.shareEventHandler(DDSSPlatformWeChat, self.shareScene, DDSSShareStateSuccess, nil);
            }
        } else if (resp.errCode == WXErrCodeUserCancel){
            if (self.shareEventHandler) {
                self.shareEventHandler(DDSSPlatformWeChat, self.shareScene, DDSSShareStateCancel, nil);
            }
        } else {
            if (self.shareEventHandler) {
                NSError *error = [NSError errorWithDomain:@"WeChat Share Error" code:resp.errCode userInfo:@{NSLocalizedDescriptionKey:resp.errStr}];
                self.shareEventHandler(DDSSPlatformWeChat, self.shareScene, DDSSShareStateFail, error);
            }
        }
        self.shareEventHandler = nil;
    }
}

@end
