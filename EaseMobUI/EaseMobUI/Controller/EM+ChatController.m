//
//  EM+ChatController.m
//  EaseMobUI
//
//  Created by 周玉震 on 15/7/1.
//  Copyright (c) 2015年 周玉震. All rights reserved.
//

#import "EM+ChatController.h"
#import "UIColor+Hex.h"
#import "MBProgressHUD.h"
#import "EM+LocationController.h"
#import "EM+ChatMessageModel.h"
#import "EM+ChatMessageManager.h"
#import "EM+ChatDBM.h"

#import <MediaPlayer/MediaPlayer.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, ALERT_ACTION) {
    ALERT_ACTION_TAP_UNKOWN = 0,
    ALERT_ACTION_TAP_URL,
    ALERT_ACTION_TAP_PHONE,
    ALERT_ACTION_TAP_TEXT,
    ALERT_ACTION_TAP_IMAGE,
    ALERT_ACTION_TAP_VOICE,
    ALERT_ACTION_TAP_VIDEO,
    ALERT_ACTION_TAP_LOCATION,
    ALERT_ACTION_TAP_FILE,
    ALERT_ACTION_PRESS_UNKOWN,
    ALERT_ACTION_PRESS_URL,
    ALERT_ACTION_PRESS_PHONE,
    ALERT_ACTION_PRESS_TEXT,
    ALERT_ACTION_PRESS_IMAGE,
    ALERT_ACTION_PRESS_VOICE,
    ALERT_ACTION_PRESS_VIDEO,
    ALERT_ACTION_PRESS_LOCATION,
    ALERT_ACTION_PRESS_FILE,
};

@interface EM_ChatController()<UITableViewDataSource,
UITableViewDelegate,
UIImagePickerControllerDelegate,
UINavigationControllerDelegate,
UIActionSheetDelegate,
EM_MessageToolBarDelegate,
EM_ChatMessageCellDelegate,
EM_LocationControllerDelegate,
EM_ChatMessageManagerDelegate,
EMChatManagerDelegate,
EMCallManagerDelegate,
EMDeviceManagerDelegate>

@property (nonatomic, strong) EMConversation *conversation;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) NSMutableArray *imageDataArray;
@property (nonatomic, strong) NSMutableArray *voiceDataArray;

@property (nonatomic, strong) UIImagePickerController *imagePicker;
@property (nonatomic, strong) UIMenuController *menuController;

@end

@implementation EM_ChatController{
    dispatch_queue_t _messageQueue;
    NSIndexPath *longPressIndexPath;
}

- (instancetype)initWithChatter:(NSString *)chatter conversationType:(EMConversationType)conversationType{
    self = [super init];
    if (self) {
        _chatter = chatter;
        _conversationType = conversationType;
        _conversation = [[EaseMob sharedInstance].chatManager conversationForChatter:_chatter conversationType:_conversationType];
        [_conversation markAllMessagesAsRead:YES];
        
        switch (_conversationType) {
            case eConversationTypeChat:
                _messageType = eMessageTypeChat;
                break;
            case eConversationTypeGroupChat:
                _messageType = eMessageTypeGroupChat;
                break;
            case eConversationTypeChatRoom:
                _messageType = eMessageTypeChatRoom;
                break;
        }
        
        _dataSource = [[NSMutableArray alloc]init];
        _imageDataArray = [[NSMutableArray alloc]init];
        _voiceDataArray = [[NSMutableArray alloc]init];
        
        self.title = _chatter;
        self.hidesBottomBarWhenPushed = YES;
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    }
    return self;
}

- (void)viewDidLoad{
    [super viewDidLoad];
    
    _chatTableView = [[EM_ChatTableView alloc]initWithFrame:self.view.frame];
    _chatTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _chatTableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _chatTableView.dataSource = self;
    _chatTableView.delegate = self;
    [self.view addSubview:_chatTableView];
    
    MJRefreshGifHeader *header = [MJRefreshGifHeader headerWithRefreshingTarget:self refreshingAction:@selector(loadMoreMessage:animated:)];
    [header setImages:nil forState:MJRefreshStateIdle];
    [header setImages:nil forState:MJRefreshStatePulling];
    [header setImages:nil forState:MJRefreshStateRefreshing];
    [header setImages:nil forState:MJRefreshStateWillRefresh];
    [header setImages:nil forState:MJRefreshStateNoMoreData];
    _chatTableView.header = header;
    
    MJRefreshBackGifFooter *footer = [MJRefreshBackGifFooter footerWithRefreshingTarget:self refreshingAction:@selector(showKeyboardOrTool)];
    [footer setTitle:@"" forState:MJRefreshStateIdle];
    [footer setTitle:@"" forState:MJRefreshStatePulling];
    [footer setTitle:@"" forState:MJRefreshStateRefreshing];
    [footer setTitle:@"" forState:MJRefreshStateWillRefresh];
    [footer setTitle:@"" forState:MJRefreshStateNoMoreData];
    _chatTableView.footer = footer;
    
    _chatToolBarView = [[EM_ChatToolBar alloc]initWithConfig:[EM_ChatUIConfig defaultConfig]];
    _chatToolBarView.frame = CGRectMake(0, self.view.frame.size.height - HEIGHT_INPUT_OF_DEFAULT, self.view.frame.size.width, HEIGHT_INPUT_OF_DEFAULT + HEIGHT_MORE_TOOL_OF_DEFAULT);
    _chatToolBarView.chatTableView = _chatTableView;
    _chatToolBarView.delegate = self;
    [self.view addSubview:_chatToolBarView];
    
    [[EaseMob sharedInstance].chatManager removeDelegate:self];
    [[EaseMob sharedInstance].chatManager addDelegate:self delegateQueue:nil];
    
    [[EaseMob sharedInstance].callManager removeDelegate:self];
    [[EaseMob sharedInstance].callManager addDelegate:self delegateQueue:nil];
    
    _messageQueue = dispatch_queue_create("EaseMob", NULL);
    
    [self loadMoreMessage:YES animated:NO];
    
    [self queryEditor];
}

- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    _isShow = YES;
}

- (void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    _isShow = NO;
}

- (void)didReceiveMemoryWarning{
    [self saveEditor];
}

- (void)dealloc{
    [self saveEditor];
}

- (UIImagePickerController *)imagePicker{
    if (!_imagePicker) {
        _imagePicker = [[UIImagePickerController alloc]init];
        _imagePicker.delegate = self;
    }
    return _imagePicker;
}

- (void)saveEditor{
    NSString *editor = _chatToolBarView.inputToolView.editor;
    
    EM_ChatConversation *conversation = [[EM_ChatConversation alloc]init];
    conversation.conversationChatter = self.conversation.chatter;
    conversation.conversationType = self.conversation.conversationType;
    conversation.conversationEditor = editor;
    
    if (editor && editor > 0) {
        BOOL update = [EM_ChatDBM updateConversation:conversation];
        if (!update) {
            [EM_ChatDBM insertConversation:conversation];
        }
    }else{
        [EM_ChatDBM deleteConversation:conversation];
    }
}

- (void)queryEditor{
    EM_ChatConversation *conversation = [EM_ChatDBM queryConversation:self.conversation.chatter];
    if (conversation && conversation.conversationEditor && conversation.conversationEditor.length > 0) {
        _chatToolBarView.inputToolView.editor = conversation.conversationEditor;
    }
}

#pragma mark - sendMessage
- (void)sendMessage:(EMMessage *)message{
    [[EaseMob sharedInstance].chatManager asyncSendMessage:message progress:nil];
}

- (void)sendMessageBody:(id<IEMMessageBody>)messageBody{
    EMMessage *retureMsg = [[EMMessage alloc]initWithReceiver:_conversation.chatter bodies:[NSArray arrayWithObject:messageBody]];
    retureMsg.messageType = _messageType;
    [self sendMessage:retureMsg];
}

- (EM_ChatMessageModel*)formatMessage:(EMMessage *)message{
    EM_ChatMessageModel *messageModel = [[EM_ChatMessageModel alloc]initWithMessage:message];
    NSString *loginChatter = [[EaseMob sharedInstance].chatManager loginInfo][kSDKUsername];
    messageModel.sender = [messageModel.chatter isEqualToString:loginChatter];
    return messageModel;
}

- (void)addMessage:(EMMessage *)message{
    EM_ChatMessageModel *messageModel = [self formatMessage:message];
    [self continuousMessage:messageModel];
    [self signMessage:messageModel];
    
    [_dataSource addObject:messageModel];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(_dataSource.count - 1) inSection:0];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_chatTableView beginUpdates];
        [_chatTableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [_chatTableView endUpdates];
        [_chatTableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
    });
}

//连续播放语音、图片
- (void)continuousMessage:(EM_ChatMessageModel *)message{
    if (message.bodyType == eMessageBodyType_Image) {
        [_imageDataArray addObject:message];
    }else if (message.bodyType == eMessageBodyType_Voice){
        [_voiceDataArray addObject:message];
    }
}

//标记图片是否被查看、语音是否听过、视频是否看过
- (void)signMessage:(EM_ChatMessageModel *)message{
    if (message.sender){
        return;
    }
    message.messageDetailsState.details = [EM_ChatDBM queryMessageDetails:message.messageDetailsState];
}

- (void)reloadMessage:(EMMessage *)message{
    EM_ChatMessageModel *messageModel = [self formatMessage:message];
    NSInteger index = [_dataSource indexOfObject:messageModel];
    if (index < 0 || index >= _dataSource.count){
        return;
    }
    
    [_dataSource replaceObjectAtIndex:index withObject:messageModel];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_chatTableView beginUpdates];
        [_chatTableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [_chatTableView endUpdates];
    });
}

#pragma mark - loadData
- (void)loadMoreMessage:(BOOL)scrollBottom animated:(BOOL)animated{
    long long timestamp = ([NSDate date].timeIntervalSince1970 + 1) * 1000;
    if (_dataSource.count > 0) {
        EM_ChatMessageModel *message = [_dataSource firstObject];
        timestamp = message.timestamp;
    }
    
    dispatch_async(_messageQueue,^{
        NSArray *messages = [_conversation loadNumbersOfMessages:20 before:timestamp];
        if (messages.count > 0) {
            for (NSInteger i = messages.count - 1; i >= 0; i--) {
                EM_ChatMessageModel *messageModel = [self formatMessage:messages[i]];
                [self continuousMessage:messageModel];
                [self signMessage:messageModel];
                
                [_dataSource insertObject:messageModel atIndex:0];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [_chatTableView reloadData];
                if (scrollBottom) {
                    [_chatTableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:_dataSource.count - 1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:animated];
                }
            });
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [_chatTableView.header endRefreshing];
        });
    });
}

- (void)showKeyboardOrTool{
    [_chatTableView.footer endRefreshing];
    if (!_chatToolBarView.keyboardVisible && !_chatToolBarView.moreToolVisble) {
        [_chatToolBarView pullUpShow];
    }
}

#pragma mark - EM_MessageToolBarDelegate
- (void)messageToolBar:(EM_ChatToolBar *)toolBar didShowToolOrKeyboard:(BOOL)isShow{
    if (isShow && _dataSource.count > 0) {
        [_chatTableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:_dataSource.count - 1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:YES];
    }
}

//InputTool
- (BOOL)messageToolBar:(EM_ChatToolBar *)toolBar shouldSeneMessage:(NSString *)message{
    NSLog(@"是否允许发送消息 - %@",message);
    return YES;
}
- (void)messageToolBar:(EM_ChatToolBar *)toolBar didSendMessagee:(NSString *)message{
    NSLog(@"发送消息 - %@",message);
    EMChatText *text = [[EMChatText alloc] initWithText:message];
    EMTextMessageBody *body = [[EMTextMessageBody alloc] initWithChatObject:text];
    [self sendMessageBody:body];
}

//MoroTool
- (void)messageToolBar:(EM_ChatToolBar *)toolBar didSelectedActionWithName:(NSString *)action{
    NSLog(@"动作 - %@",action);
    
    if ([action isEqualToString:kActionNameImage]) {
        
        BOOL photoAvailable = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary];
        if (photoAvailable) {
            self.imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            self.imagePicker.mediaTypes = @[(NSString *)kUTTypeImage];
            [self presentViewController:self.imagePicker animated:YES completion:NULL];
        }else{
            [self showHint:EM_ChatString(@"error.device.not_support_photo_library")];
        }
        
    }else if ([action isEqualToString:kActionNameCamera]){
        
        BOOL cameraAvailable = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
        if (cameraAvailable) {
            self.imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
            self.imagePicker.cameraDevice = UIImagePickerControllerCameraDeviceRear;
            self.imagePicker.mediaTypes = @[(NSString *)kUTTypeImage,(NSString *)kUTTypeMovie];
            self.imagePicker.videoMaximumDuration = 180;
            [self presentViewController:self.imagePicker animated:YES completion:NULL];
        }else{
            [self showHint:EM_ChatString(@"error.device.not_support_camera")];
        }
    }else if ([action isEqualToString:kActionNameVoice]){
        [[EaseMob sharedInstance].callManager asyncMakeVoiceCall:_chatter timeout:60 error:nil];
    }else if ([action isEqualToString:kActionNameVideo]){
        [[EaseMob sharedInstance].callManager asyncMakeVideoCall:_chatter timeout:60 error:nil];
    }else if ([action isEqualToString:kActionNameLocation]){
        
        EM_LocationController *locationController = [[EM_LocationController alloc]init];
        locationController.delegate = self;
        [self.navigationController pushViewController:locationController animated:YES];
    }else if ([action isEqualToString:kActionNameFile]){
        NSData *data = UIImageJPEGRepresentation([UIImage imageNamed:RES_IMAGE_TOOL(@"tool_play")],1.0);
        EMChatFile *chatFile =  [[EMChatFile alloc]initWithData:data displayName:@"tool_play.png"];
        EMFileMessageBody *body = [[EMFileMessageBody alloc]initWithChatObject:chatFile];
        [self sendMessageBody:body];
    }else{
        
    }
}
- (BOOL)messageToolBar:(EM_ChatToolBar *)toolBar shouldRecord:(UIView *)view{
    NSLog(@"是否允许录音");
    
    __block BOOL bCanRecord = YES;
    if ([[[UIDevice currentDevice] systemVersion] compare:@"7.0"] != NSOrderedAscending){
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        if ([audioSession respondsToSelector:@selector(requestRecordPermission:)]) {
            [audioSession performSelector:@selector(requestRecordPermission:) withObject:^(BOOL granted) {
                bCanRecord = granted;
            }];
        }
    }
    
    return bCanRecord;
}
- (void)messageToolBar:(EM_ChatToolBar *)toolBar didStartRecord:(UIView *)view{
    NSLog(@"开始录音");
}

- (void)messageToolBar:(EM_ChatToolBar *)toolBar didCancelRecord:(UIView *)view{
    NSLog(@"取消录音");
}

- (void)messageToolBar:(EM_ChatToolBar *)toolBar didEndRecord:(NSString *)name record:(NSString *)recordPath duration:(NSInteger)duration{
    NSLog(@"结束录音  %@",name);
    EMChatVoice *voice = [[EMChatVoice alloc] initWithFile:recordPath displayName:name];
    voice.duration = duration;
    EMVoiceMessageBody *body = [[EMVoiceMessageBody alloc] initWithChatObject:voice];
    [self sendMessageBody:body];
}

- (void)messageToolBar:(EM_ChatToolBar *)toolBar didRecordError:(NSError *)error{
    if (!error) {
        [self showHint:EM_ChatString(@"error.record.too_short")];
    }else{
        [self showHint:EM_ChatString(@"error.record.failure")];
    }
}

#pragma mark - EM_ChatMessageCellDelegate
- (void)chatMessageCell:(EM_ChatMessageCell *)cell didTapAvatarWithChatter:(NSString *)chatter indexPath:(NSIndexPath *)indexPath{
    NSString *loginChatter = [[EaseMob sharedInstance].chatManager loginInfo][kSDKUsername];
    if ([chatter isEqualToString:loginChatter]) {
        [self showHint:@"点击了自己的头像"];
    }else{
        [self showHint:@"点击了对方的头像"];
    }

}

- (void)chatMessageCell:(EM_ChatMessageCell *)cell resendMessageWithMessage:(EM_ChatMessageModel *)message indexPath:(NSIndexPath *)indexPath{
    
}

- (void)chatMessageCell:(EM_ChatMessageCell *)cell didTapMessageWithUserInfo:(NSDictionary *)userInfo indexPath:(NSIndexPath *)indexPath{
    EM_ChatMessageModel *messageModel = userInfo[kHandleActionMessage];
    
    NSString *handleAction = userInfo[kHandleActionName];
    if ([handleAction isEqualToString:HANDLE_ACTION_URL]) {
        NSURL *url = userInfo[kHandleActionValue];
        [[UIApplication sharedApplication] openURL:url];
    }else if ([handleAction isEqualToString:HANDLE_ACTION_PHONE]){
        NSString *phone = userInfo[kHandleActionValue];
        UIActionSheet *sheet = [[UIActionSheet alloc]initWithTitle:[NSString stringWithFormat:EM_ChatString(@"hint.may_phone"),phone] delegate:self cancelButtonTitle:EM_ChatString(@"common.cancel") destructiveButtonTitle:nil otherButtonTitles:EM_ChatString(@"common.call"),EM_ChatString(@"common.copy"),nil];
        sheet.tag = ALERT_ACTION_TAP_PHONE;
        [sheet showInView:self.view];
    }else if ([handleAction isEqualToString:HANDLE_ACTION_TEXT]){
        
    }else if ([handleAction isEqualToString:HANDLE_ACTION_IMAGE]){
        NSInteger index = [_imageDataArray indexOfObject:messageModel];
        if (index >= 0 && index < _imageDataArray.count) {
            [[EM_ChatMessageManager defaultManager] showBrowserWithImagesMessage:_imageDataArray index:index];
        }else{
            [[EM_ChatMessageManager defaultManager] showBrowserWithImagesMessage:@[messageModel] index:0];
        }
    }else if ([handleAction isEqualToString:HANDLE_ACTION_VOICE]){
        [EM_ChatMessageManager defaultManager].delegate = self;
        if (messageModel.messageDetailsState.checking) {
            messageModel.messageDetailsState.checking = NO;
            [[EM_ChatMessageManager defaultManager] stopVoice];
            [_chatTableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        }else{
            NSInteger index = [_voiceDataArray indexOfObject:messageModel];
            if (index >= 0 && index < _voiceDataArray.count) {
                [[EM_ChatMessageManager defaultManager] playVoice:_voiceDataArray index:index];
            }else{
                [[EM_ChatMessageManager defaultManager] playVoice:@[messageModel] index:0];
            }
        }
    }else if ([handleAction isEqualToString:HANDLE_ACTION_VIDEO]){
        [[EM_ChatMessageManager defaultManager] showBrowserWithVideoMessage:messageModel];
    }else if ([handleAction isEqualToString:HANDLE_ACTION_LOCATION]){
        EMLocationMessageBody *locationBody = messageModel.messageBody;
        EM_LocationController *locationController = [[EM_LocationController alloc]initWithLocation:CLLocationCoordinate2DMake(locationBody.latitude, locationBody.longitude)];
        [self.navigationController pushViewController:locationController animated:YES];
    }else if ([handleAction isEqualToString:HANDLE_ACTION_FILE]){
        
    }else{
        
    }
    
    if (!messageModel.sender
        && !messageModel.messageDetailsState.details
        && ![handleAction isEqualToString:HANDLE_ACTION_URL]
        && ![handleAction isEqualToString:HANDLE_ACTION_PHONE]
        && ![handleAction isEqualToString:HANDLE_ACTION_TEXT]){
        messageModel.messageDetailsState.details = YES;
        [EM_ChatDBM updateMessageDetails:messageModel.messageDetailsState];
    }
}

- (void)chatMessageCell:(EM_ChatMessageCell *)cell didLongPressMessageWithUserInfo:(NSDictionary *)userInfo indexPath:(NSIndexPath *)indexPath{
    
    NSString *handleAction = userInfo[kHandleActionName];
    if ([handleAction isEqualToString:HANDLE_ACTION_URL]) {
        NSURL *url = userInfo[kHandleActionValue];
        UIActionSheet *sheet = [[UIActionSheet alloc]initWithTitle:[NSString stringWithFormat:EM_ChatString(@"hint.may_link"),url] delegate:self cancelButtonTitle:EM_ChatString(@"common.cancel") destructiveButtonTitle:nil otherButtonTitles:EM_ChatString(@"common.open"),EM_ChatString(@"common.copy"),nil];
        sheet.tag = ALERT_ACTION_PRESS_URL;
        [sheet showInView:self.view];
    }else if ([handleAction isEqualToString:HANDLE_ACTION_PHONE]){
        NSString *phone = userInfo[kHandleActionValue];
        UIActionSheet *sheet = [[UIActionSheet alloc]initWithTitle:[NSString stringWithFormat:EM_ChatString(@"hint.may_phone"),phone] delegate:self cancelButtonTitle:EM_ChatString(@"common.cancel") destructiveButtonTitle:nil otherButtonTitles:EM_ChatString(@"common.call"),EM_ChatString(@"common.copy"),nil];
        sheet.tag = ALERT_ACTION_PRESS_PHONE;
        [sheet showInView:self.view];
    }else{
        longPressIndexPath = indexPath;
        EM_ChatMessageModel *messageModel = _dataSource[indexPath.row];
        [self showMenuViewControllerAtIndexPath:indexPath withMessage:messageModel];
    }
}

#pragma mark - ShowMenu
- (void)showMenuViewControllerAtIndexPath:(NSIndexPath *)indexPath withMessage:(EM_ChatMessageModel *)message{
    
    if (!_menuController) {
        _menuController = [UIMenuController sharedMenuController];
    }
    
    NSMutableArray *menuItems = [[NSMutableArray alloc]init];
    if (message.bodyType == eMessageBodyType_Text) {
        //复制
        UIMenuItem *copyItme = [[UIMenuItem alloc]initWithTitle:EM_ChatString(@"common.copy") action:@selector(copyMessage:)];
        [menuItems addObject:copyItme];
    }else if (message.bodyType == eMessageBodyType_Image){
        //收藏到表情
        UIMenuItem *collectFaceItem = [[UIMenuItem alloc]initWithTitle:EM_ChatString(@"common.collect_face") action:@selector(collectMessageFace:)];
        [menuItems addObject:collectFaceItem];
    }else if (message.bodyType == eMessageBodyType_File){
        //下载,如果未下载
        EMFileMessageBody *messageBody = (EMFileMessageBody *)message.messageBody;
        if (messageBody.attachmentDownloadStatus == EMAttachmentNotStarted) {
            UIMenuItem *downloadItem = [[UIMenuItem alloc]initWithTitle:EM_ChatString(@"common.download") action:@selector(downloadMessageFile:)];
            [menuItems addObject:downloadItem];
        }
    }
    
    if (message.bodyType != eMessageBodyType_Video) {
        //收藏
        UIMenuItem *collectItem = [[UIMenuItem alloc]initWithTitle:EM_ChatString(@"common.collect") action:@selector(collectMessage:)];
        [menuItems addObject:collectItem];
    }
    
    if (message.bodyType != eMessageBodyType_Voice) {
        //转发
        
        UIMenuItem *forwardItem = [[UIMenuItem alloc]initWithTitle:EM_ChatString(@"common.forward") action:@selector(forwardMessage:)];
        [menuItems addObject:forwardItem];
        
        //转发多条
    }

    //撤回
    if (message.sender) {
        UIMenuItem *revocationItem = [[UIMenuItem alloc]initWithTitle:EM_ChatString(@"common.revocation") action:@selector(revocationMessage:)];
        [menuItems addObject:revocationItem];
    }
    
    //删除
    UIMenuItem *deleteItem = [[UIMenuItem alloc]initWithTitle:EM_ChatString(@"common.delete") action:@selector(deleteMessage:)];
    [menuItems addObject:deleteItem];
    
    [_menuController setMenuItems:menuItems];
    
    EM_ChatMessageCell *cell = (EM_ChatMessageCell *)[_chatTableView cellForRowAtIndexPath:indexPath];
    UIView *targetView = cell.bubbleView;
    
    if (_chatToolBarView.keyboardVisible) {
        _chatToolBarView.inputToolView.overrideNextResponder = targetView;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(menuDidHide:) name:UIMenuControllerDidHideMenuNotification object:nil];
    }else{
        [targetView becomeFirstResponder];
    }
    
    [_menuController setTargetRect:targetView.frame inView:targetView.superview];
    [_menuController setMenuVisible:YES animated:YES];
}

- (void)menuDidHide:(NSNotification*)notification {
    _chatToolBarView.inputToolView.overrideNextResponder = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIMenuControllerDidHideMenuNotification object:nil];
}

- (void)copyMessage:(id)sender{
    
}

- (void)collectMessageFace:(id)sender{
    
}

- (void)downloadMessageFile:(id)sender{
    
}

- (void)collectMessage:(id)sender{
    
}

- (void)forwardMessage:(id)sender{
    
}

- (void)revocationMessage:(id)sender{
    
}

- (void)deleteMessage:(id)sender{
    
}

#pragma mark - EM_ChatMessageManagerDelegate
- (void)playStartWithMessage:(id)startMessage{
    NSInteger index = [_dataSource indexOfObject:startMessage];
    if (index >= 0 && index < _dataSource.count) {
        [_chatTableView reloadData];
    }
}

- (void)playCompletionWithMessage:(id)completionMessage nextMessage:(id)nextMessage{
    if (completionMessage) {
        NSMutableArray *reloadArray = [[NSMutableArray alloc]init];
        
        NSInteger index = [_dataSource indexOfObject:completionMessage];
        if (index >= 0 && index < _dataSource.count) {
            [reloadArray addObject:[NSIndexPath indexPathForRow:index inSection:0]];
        }
        
        if (nextMessage) {
            index = [_dataSource indexOfObject:nextMessage];
            if (index >= 0 && index < _dataSource.count) {
                [reloadArray addObject:[NSIndexPath indexPathForRow:index inSection:0]];
            }
        }
        [_chatTableView reloadRowsAtIndexPaths:reloadArray withRowAnimation:UITableViewRowAnimationNone];
        EM_ChatMessageModel *messageModel = completionMessage;
        if (!messageModel.sender) {
            messageModel.messageDetailsState.details = YES;
            [EM_ChatDBM updateMessageDetails:messageModel.messageDetailsState];
        }
    }
}

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex{
    switch (actionSheet.tag) {
        case ALERT_ACTION_TAP_PHONE:
        case ALERT_ACTION_PRESS_PHONE:{
            NSString *title = actionSheet.title;
            NSRange startRange = [title rangeOfString:@"["];
            NSRange endRange = [title rangeOfString:@"]"];
            NSString *phone = [title substringWithRange:NSMakeRange(startRange.location + 1, endRange.location - startRange.location - 1)];
            if (buttonIndex == 0) {
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"tel://%@",phone]]];
            }else if (buttonIndex == 1){
                UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                pasteboard.string = phone;
            }
        }
            break;
        case ALERT_ACTION_PRESS_URL:{
            NSString *title = actionSheet.title;
            NSRange startRange = [title rangeOfString:@"["];
            NSRange endRange = [title rangeOfString:@"]"];
            NSString *url = [title substringWithRange:NSMakeRange(startRange.location + 1, endRange.location - startRange.location - 1)];
            if (buttonIndex == 0) {
                [[UIApplication sharedApplication] openURL:[[NSURL alloc] initWithString:url]];
            }else if (buttonIndex == 1){
                UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                pasteboard.string = url;
            }
        }
        default:
            break;
    }
}

#pragma mark - EM_LocationControllerDelegate
-(void)sendLocationLatitude:(double)latitude longitude:(double)longitude andAddress:(NSString *)address{
    EMChatLocation *chatLocation = [[EMChatLocation alloc] initWithLatitude:latitude longitude:longitude address:address];
    EMLocationMessageBody *body = [[EMLocationMessageBody alloc] initWithChatObject:chatLocation];
    [self sendMessageBody:body];
}

#pragma mark - UIImagePickerControllerDelegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info{
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    NSString *mediaType = info[UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
        UIImage *orgImage = info[UIImagePickerControllerOriginalImage];
        EMChatImage *chatImage = [[EMChatImage alloc] initWithUIImage:orgImage displayName:[NSString stringWithFormat:@"%d%d%@",(int)[NSDate date].timeIntervalSince1970,arc4random() % 100000,@".jpg"]];
        EMImageMessageBody *body = [[EMImageMessageBody alloc] initWithImage:chatImage thumbnailImage:nil];
        [self sendMessageBody:body];
    }else if([mediaType isEqualToString:(NSString *)kUTTypeMovie]){
        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        
        NSURL *mp4 = [self convert2Mp4:videoURL];
        NSFileManager *fileman = [NSFileManager defaultManager];
        if ([fileman fileExistsAtPath:videoURL.path]) {
            NSError *error = nil;
            [fileman removeItemAtURL:videoURL error:&error];
            if (error) {
                NSLog(@"failed to remove file, error:%@.", error);
            }
        }
        EMChatVideo *chatVideo = [[EMChatVideo alloc] initWithFile:[mp4 relativePath] displayName:[NSString stringWithFormat:@"%d%d%@",(int)[NSDate date].timeIntervalSince1970,arc4random() % 100000,@".mp4"]];
        EMVideoMessageBody *body = [[EMVideoMessageBody alloc]initWithChatObject:chatVideo];
        [self sendMessageBody:body];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker{
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (NSURL *)convert2Mp4:(NSURL *)movUrl {
    NSURL *mp4Url = nil;
    AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:movUrl options:nil];
    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:avAsset];
    
    if ([compatiblePresets containsObject:AVAssetExportPresetHighestQuality]) {
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]initWithAsset:avAsset
                                                                              presetName:AVAssetExportPresetHighestQuality];
        mp4Url = [movUrl copy];
        mp4Url = [mp4Url URLByDeletingPathExtension];
        mp4Url = [mp4Url URLByAppendingPathExtension:@"mp4"];
        exportSession.outputURL = mp4Url;
        exportSession.shouldOptimizeForNetworkUse = YES;
        exportSession.outputFileType = AVFileTypeMPEG4;
        dispatch_semaphore_t wait = dispatch_semaphore_create(0l);
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            switch ([exportSession status]) {
                case AVAssetExportSessionStatusFailed: {
                    NSLog(@"failed, error:%@.", exportSession.error);
                } break;
                case AVAssetExportSessionStatusCancelled: {
                    NSLog(@"cancelled.");
                } break;
                case AVAssetExportSessionStatusCompleted: {
                    NSLog(@"completed.");
                } break;
                default: {
                    NSLog(@"others.");
                } break;
            }
            dispatch_semaphore_signal(wait);
        }];
        long timeout = dispatch_semaphore_wait(wait, DISPATCH_TIME_FOREVER);
        if (timeout) {
            NSLog(@"timeout.");
        }
        if (wait) {
            //dispatch_release(wait);
            wait = nil;
        }
    }
    
    return mp4Url;
}

#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return _dataSource.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    EM_ChatMessageModel *message = _dataSource[indexPath.row];
    NSString *cellId = [EM_ChatMessageCell cellIdFormMessageBodyType:message.bodyType];
    
    EM_ChatMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [EM_ChatMessageCell cellFromMessageBodyType:message.bodyType reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.message = message;
    cell.indexPath = indexPath;
    cell.delegate = self;
    
    return cell;
}

#pragma mark - UITableViewDelegate
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    EM_ChatMessageModel *message = _dataSource[indexPath.row];
    return [EM_ChatMessageCell heightForCellWithMessage:message maxWidth:tableView.bounds.size.width indexPath:indexPath];
}

#pragma mark - EMCallManagerDelegate
- (void)callSessionStatusChanged:(EMCallSession *)callSession changeReason:(EMCallStatusChangedReason)reason error:(EMError *)error{
    
}

#pragma mark - EMChatManagerChatDelegate
- (void)willSendMessage:(EMMessage *)message error:(EMError *)error{
    if (![_dataSource containsObject:message]) {
        [self addMessage:message];
    }
}

- (void)didSendMessage:(EMMessage *)message error:(EMError *)error{
    [self reloadMessage:message];
}

- (void)didReceiveMessage:(EMMessage *)message{
    if ([message.conversationChatter isEqualToString:_conversation.chatter]) {
        [self addMessage:message];
    }
}

- (void)didReceiveCmdMessage:(EMMessage *)cmdMessage{
    
}

- (void)didReceiveMessageId:(NSString *)messageId chatter:(NSString *)conversationChatter error:(EMError *)error{
    //发送消息出现错误
}

- (void)didFetchingMessageAttachments:(EMMessage *)message progress:(float)progress{
    //图片、视频缩略图,语音等下载进度
    [self reloadMessage:message];
}

- (void)didMessageAttachmentsStatusChanged:(EMMessage *)message error:(EMError *)error{
    //图片、视频缩略图,语音等下载完成
    [self reloadMessage:message];
}

- (void)didReceiveHasReadResponse:(EMReceipt *)resp{
    //已读回执
}

- (void)didReceiveHasDeliveredResponse:(EMReceipt *)resp{
    //已送达回执
}

- (void)didUnreadMessagesCountChanged{
    //未读消息数量发生变化
}

- (void)didFinishedReceiveOfflineMessages:(NSArray *)offlineMessages{
    if (offlineMessages.count > 0) {
        [_dataSource removeAllObjects];
        [self loadMoreMessage:YES animated:YES];
    }
}

- (void)didFinishedReceiveOfflineCmdMessages:(NSArray *)offlineCmdMessages{
    
}

#pragma mark - EMChatManagerGroupDelegate
- (void)group:(EMGroup *)group didLeave:(EMGroupLeaveReason)reason error:(EMError *)error{
    //聊天中,被请出
    if (_conversationType != eConversationTypeGroupChat){
        return;
    }
}

- (void)groupDidUpdateInfo:(EMGroup *)group error:(EMError *)error{
    //聊天中,群信息发生变化(成员,公告)
    if (_conversationType != eConversationTypeGroupChat){
        return;
    }
}

#pragma mark - EMChatManagerChatroomDelegate
- (void)chatroom:(EMChatroom *)chatroom occupantDidJoin:(NSString *)username{
    //聊天中,有成员加入
    if (_conversationType != eConversationTypeChatRoom){
        return;
    }
}

- (void)chatroom:(EMChatroom *)chatroom occupantDidLeave:(NSString *)username{
    //聊天中,有成员离开
    if (_conversationType != eConversationTypeChatRoom){
        return;
    }
}

- (void)beKickedOutFromChatroom:(EMChatroom *)chatroom reason:(EMChatroomBeKickedReason)reason{
    //聊天中,被请出
    if (_conversationType != eConversationTypeChatRoom){
        return;
    }
}

@end