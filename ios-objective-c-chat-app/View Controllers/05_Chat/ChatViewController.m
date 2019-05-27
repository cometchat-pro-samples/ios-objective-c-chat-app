//
//  ChatViewController.m
//  ios-objective-c-chat-app
//
//  Created by Budhabhooshan Patil on 19/02/19.
//  Copyright © 2019 Inscripts.com. All rights reserved.
//

#import "ChatViewController.h"
#import <MobileCoreServices/MobileCoreServices.h> // needed for video types
#import <AVFoundation/AVFoundation.h>
#import <QuickLook/QuickLook.h>

#import "AudioTableViewCell.h"
#import "FilesTableViewCell.h"
#import "TextTableViewCell.h"
#import "MediaTableViewCell.h"
#import "ActionTableViewCell.h"

@interface ChatEntity : NSObject

-(id) initIMessageWithEntity:(AppEntity *)appEntity;

@property (strong, nonatomic) NSString *receiverId;
@property (nonatomic) ReceiverType receiverType;
@property (strong, nonatomic) NSString *receiverName;
@property (strong , nonatomic) AppEntity *entity;
@property (nonatomic ,retain) NSString *profileURL;
@property (nonatomic ,retain) NSString *lastActiveAt;
@end

@implementation ChatEntity

-(id) initIMessageWithEntity:(AppEntity *)appEntity
{
    self = [super init];
    if(self)
    {
        
        if ([appEntity isKindOfClass:User.class]) {
            
            self.receiverId = [(User *)appEntity uid];
            self.receiverType = ReceiverTypeUser;
            self.receiverName = [(User *)appEntity name];
            self.entity = appEntity;
            self.profileURL = [(User *)appEntity avatar];
            
            self.lastActiveAt = [NSString stringWithFormat:@"%ld",(long)[(User *)appEntity lastActiveAt]];
            
        } else if ([appEntity isKindOfClass:Group.class]){
            
            self.receiverId = [(Group *)appEntity guid];
            self.receiverType = ReceiverTypeGroup;
            self.receiverName =  [(Group *)appEntity name];
            self.entity = appEntity;
            self.profileURL = [(Group *)appEntity icon];
        }
    }
    
    return self;
}

@end

static int textFiledHeight;
@interface ChatViewController ()<MessageDelegate,UINavigationControllerDelegate,UIImagePickerControllerDelegate,UIPopoverPresentationControllerDelegate,UIGestureRecognizerDelegate,QLPreviewControllerDataSource,UIDocumentPickerDelegate,AudioRecorderDelegate,AVAudioPlayerDelegate ,UserEventDelegate , AppMediaDelegate  ,AppFileDelegate , AppAudioDelegate >
@property(nonatomic , strong) AppDelegate *appDelegate;
@property (nonatomic ,strong) ActivityIndicatorView *backgroundActivityIndicatorView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@end

@implementation ChatViewController{
    
    UIDocumentPickerViewController *_documentPicker;
    UIPopoverPresentationController *_popover;
    AudioVisualizer *_audioVisualizer;
    ChatEntity *_chatEntity;
    NSString *previewUrl;
    
    double lowPassReslts;
    double lowPassReslts1;
    NSTimer *visualizerTimer;
    AudioVisualizerView *audioVisualizerView;
    AVAudioPlayer * avAudioPlayer;
    NSTextAttachment *userStatusTextAttachment;
    NSString *logged_in_user_uid;
}
@synthesize messsagesArray,messageRequest,appEntity;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self delegate].messagedelegate = self;
    
    NSInteger limit = 50;
    
    _chatEntity = [[ChatEntity alloc]initIMessageWithEntity:appEntity];
    
    if (_chatEntity.receiverType == ReceiverTypeUser)
    {
        messageRequest = [[[[[MessageRequestBuilder alloc]init]setWithUID:_chatEntity.receiverId]setWithLimit:limit] build];
        
    } else if (_chatEntity.receiverType == ReceiverTypeGroup)
    {
        messageRequest = [[[[[MessageRequestBuilder alloc]init]setWithGUID:_chatEntity.receiverId]setWithLimit:limit]build];
    }
    messsagesArray = [NSMutableArray new];
    
    [_sendMessageTextView setDelegate:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        textFiledHeight = self.sendMessageTextView.frame.size.height;
    } else {
        textFiledHeight = self.sendMessageTextView.frame.size.height + 2;
    }
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                   initWithTarget:self
                                   action:@selector(dismissKeyboard)];
    
    [self._tableView addGestureRecognizer:tap];
    
    [self configuretable];
    [self fetchNext];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error: nil];
    
    [self viewWillSetupNavigationBar];
    _backgroundActivityIndicatorView = [[ActivityIndicatorView alloc]initWithActivityIndicatorStyle:(UIActivityIndicatorViewStyleGray)];
    [__tableView setBackgroundView:_backgroundActivityIndicatorView];
    [_backgroundActivityIndicatorView startAnimating];
    [self.sendMessageTextView addSubview:self.placeholderLabel];
    self.sendMessageTextView.returnKeyType = UIReturnKeySend;
    logged_in_user_uid = [[NSUserDefaults standardUserDefaults]objectForKey:@LOGGED_IN_USER_ID];
}
-(void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    
    TypingIndicator *endTying = [[TypingIndicator alloc]initWithReceiverID:[_chatEntity receiverId] receiverType: [_chatEntity receiverType]];
    [CometChat endTypingWithIndicator:endTying];
}
- (void)actionCallAudio
{
    CallViewController *controller = [self.storyboard instantiateViewControllerWithIdentifier:@"CallViewController"];
    [controller setEntity:appEntity];
    [controller setCallType:CallTypeAudio];
    [self presentViewController:controller animated:YES completion:nil];
    
}

- (void)actionCallVideo
{
    
    CallViewController *controller = [self.storyboard instantiateViewControllerWithIdentifier:@"CallViewController"];
    [controller setEntity:appEntity];
    [controller setCallType:CallTypeVideo];
    [self presentViewController:controller animated:YES completion:nil];
}

- (AppDelegate *)delegate {
    return (AppDelegate *)[[UIApplication sharedApplication] delegate];
}
-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    
    // Initialize the refresh control.
    _refreshControl = [[UIRefreshControl alloc] init];
    [_refreshControl addTarget:self
                        action:@selector(loadPrevious)
              forControlEvents:UIControlEventValueChanged];
    [__tableView setRefreshControl:_refreshControl];
    [self delegate].usereventdelegate = self;
}
-(void)viewWillSetupNavigationBar{
    
    if (@available(iOS 11.0, *)) {
        self.navigationController.navigationBar.prefersLargeTitles = NO;
        self.navigationController.navigationBar.largeTitleTextAttributes = @{NSForegroundColorAttributeName:[UIColor whiteColor]};
        
    } else {
        // Fallback on earlier versions
    }
    
    [self.navigationController.navigationBar setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    [self.navigationController.navigationBar setTranslucent:YES];
    [self.navigationController.navigationBar setTintColor:[UIColor whiteColor]];
    UIBarButtonItem *buttonCallAudio = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"chat_callaudio"]
                                                                        style:UIBarButtonItemStylePlain target:self action:@selector(actionCallAudio)];
    UIBarButtonItem *buttonCallVideo = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"chat_callvideo"]
                                                                        style:UIBarButtonItemStylePlain target:self action:@selector(actionCallVideo)];
    self.navigationItem.rightBarButtonItems = @[buttonCallVideo, buttonCallAudio];
    
    if ([_chatEntity receiverType] == ReceiverTypeUser)
    {
        UIView *new = [self naviagtionTitle:[_chatEntity receiverName] WithStatus:[[_chatEntity lastActiveAt] sentAtToTime]];
        [self.navigationItem setTitleView:new];
        // set up naviagtion bar with typing indicator and title "USER"
    }
    else
    {
        UIView *new = [self naviagtionTitle:[_chatEntity receiverName] WithStatus:nil];
        [self.navigationItem setTitleView:new];
    }
    
}
-(void)loadPrevious{
    
    [_refreshControl beginRefreshing];
    [messageRequest fetchPreviousOnSuccess:^(NSArray<BaseMessage *> * messages) {
        
        if (messages) {
            NSIndexSet *set = [[NSIndexSet alloc]initWithIndexesInRange:NSMakeRange(0, [messages count])];
            [messsagesArray insertObjects:messages atIndexes:set];
            for (BaseMessage *object in messages) {
                [CometChat markMessageAsReadWithMessage:object];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [__tableView reloadData];
            [_refreshControl endRefreshing];
            
        });
        
    } onError:^(CometChatException * error) {
        
        NSLog(@"%@",[error errorDescription]);
        dispatch_async(dispatch_get_main_queue(), ^{
            [_refreshControl endRefreshing];
        });
    }];
}
-(void)fetchNext{
    
    [messageRequest fetchPreviousOnSuccess:^(NSArray<BaseMessage *> * messages) {
        
        if (messages) {
            [messsagesArray addObjectsFromArray:messages];
            
            for (BaseMessage *object in messages) {
                [CometChat markMessageAsReadWithMessage:object];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [__tableView reloadData];
            [_backgroundActivityIndicatorView stopAnimating];
            
        });
        
    } onError:^(CometChatException * error) {
        
        NSLog(@"%@",[error errorDescription]);
        dispatch_async(dispatch_get_main_queue(), ^{
            [_backgroundActivityIndicatorView stopAnimating];
        });
    }];
}
-(void)configuretable{
    
    __tableView.delegate = self;
    __tableView.dataSource = self;
    __tableView.estimatedRowHeight = 60;
    __tableView.rowHeight = UITableViewAutomaticDimension;
    __tableView.estimatedSectionFooterHeight = 0.0f;
    __tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    
}
-(void)addBorderToView:(UIView *)_aView
{
    CGFloat borderWidth = 1;
    [_border removeFromSuperlayer];
    _border = [CALayer layer];
    _border.borderColor = [UIColor lightGrayColor].CGColor;
    _border.frame = CGRectMake(0, - borderWidth, _aView.frame.size.width,borderWidth);
    _border.borderWidth = borderWidth;
    [_aView.layer addSublayer:_border];
    
}
- (UILabel *) placeholderLabel {
    if (!_placeholderLabel) {
        _placeholderLabel = [[UILabel alloc]initWithFrame:CGRectMake(8.0f, 2.0f, _sendMessageTextView.frame.size.width - 16.0f, _sendMessageTextView.frame.size.height - 4.0f)];
        _placeholderLabel.userInteractionEnabled = NO;
        _placeholderLabel.backgroundColor = [UIColor clearColor];
        _placeholderLabel.font = [UIFont systemFontOfSize:16.0];
        _placeholderLabel.textColor = [UIColor lightGrayColor];
        _placeholderLabel.text = NSLocalizedString(@"Write a messsage", @"");
        _placeholderLabel.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    }
    
    return _placeholderLabel;
}
#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return messsagesArray.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell *cell = [[UITableViewCell alloc] init];
    [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
    [cell setTag:[indexPath row]];
    
    BaseMessage *message = [messsagesArray objectAtIndex:[indexPath row]];
    
    if ([message isKindOfClass:TextMessage.class]) {
        
        TextMessage *textMessage = (TextMessage *)message;
        
        TextTableViewCell *textcell = [[TextTableViewCell alloc]initWithStyle:(UITableViewCellStyleDefault) reuseIdentifier: [TextTableViewCell reuseIdentifier]];
        
        if ([[textMessage senderUid] isEqualToString:logged_in_user_uid]) {
            
            [textcell bind:textMessage withTailDirection:(MessageBubbleViewButtonTailDirectionRight)];
            return textcell;
        } else {
            
            [textcell bind:textMessage withTailDirection:(MessageBubbleViewButtonTailDirectionLeft)];
            return textcell;
        }
        
    }else if ([message isKindOfClass:MediaMessage.class]){
        
        MediaMessage *mediaMessage = (MediaMessage *)message;
        
        FilesTableViewCell *filesCell = [[FilesTableViewCell alloc]initWithStyle:(UITableViewCellStyleDefault) reuseIdentifier: [FilesTableViewCell reuseIdentifier]];
        filesCell.delegate = self;
        
        if (message.messageType == MessageTypeFile) {
            
            if ([[mediaMessage senderUid] isEqualToString:logged_in_user_uid]) {
                [filesCell bind:mediaMessage withTailDirection:(MessageBubbleViewButtonTailDirectionRight) indexPath:indexPath];
                [filesCell setTag:[indexPath row]];
                return filesCell;
            } else {
                [filesCell bind:mediaMessage withTailDirection:(MessageBubbleViewButtonTailDirectionLeft) indexPath:indexPath];
                [filesCell setTag:[indexPath row]];
                return filesCell;
            }
        }
        if (message.messageType == MessageTypeVideo || message.messageType == MessageTypeImage) {
            
            MediaTableViewCell *mediaCell = [[MediaTableViewCell alloc]initWithStyle:(UITableViewCellStyleDefault) reuseIdentifier: [MediaTableViewCell reuseIdentifier]];
            mediaCell.delegate = self;
            if ([[mediaMessage senderUid] isEqualToString:logged_in_user_uid]) {
                [mediaCell bind:mediaMessage withTailDirection:(MessageBubbleViewButtonTailDirectionRight) indexPath:indexPath];
                [mediaCell setTag:[indexPath row]];
                return mediaCell;
                
            } else {
                
                [mediaCell bind:mediaMessage withTailDirection:(MessageBubbleViewButtonTailDirectionLeft) indexPath:indexPath];
                [mediaCell setTag:[indexPath row]];
                return mediaCell;
            }
        }
        if (message.messageType == MessageTypeAudio) {
            
            AudioTableViewCell *audioCell = [[AudioTableViewCell alloc]initWithStyle:(UITableViewCellStyleDefault) reuseIdentifier:[AudioTableViewCell reuseIdentifier]];
            audioCell.delegate = self ;
            
            if ([[mediaMessage senderUid] isEqualToString:logged_in_user_uid]) {
                [audioCell bind:mediaMessage withTailDirection:(MessageBubbleViewButtonTailDirectionRight) indexPath:indexPath];
                [audioCell  setTag:[indexPath row]];
                return audioCell;
            }else {
                [audioCell bind:mediaMessage withTailDirection:(MessageBubbleViewButtonTailDirectionLeft) indexPath:indexPath];
                [audioCell  setTag:[indexPath row]];
                return audioCell;
            }
        }
    }else if ([message isKindOfClass:ActionMessage.class]){
        
        ActionMessage *action = (ActionMessage *)message;
        
        ActionTableViewCell *someCell = (ActionTableViewCell *)[tableView dequeueReusableCellWithIdentifier:[ActionTableViewCell reuseIdentifier]];
        if (!someCell) {
            someCell = [[ActionTableViewCell alloc]initWithStyle:(UITableViewCellStyleDefault) reuseIdentifier: [ActionTableViewCell reuseIdentifier]];
        }
        if (someCell) {
            [someCell bind:[action message]];
        }
        return someCell;
    }else if ([message isKindOfClass:Call.class]){
        
        Call *callMessage = (Call *)message;
        
        NSError *jsonError;
        NSData *objectData = [[callMessage rawData] dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:objectData
                                                             options:NSJSONReadingMutableContainers
                                                               error:&jsonError];
        NSString *from , *to;
        
        from = [[[json objectForKey:@"by"]objectForKey:@"entity"]objectForKey:@"name"];
        to  = [[[json objectForKey:@"for"]objectForKey:@"entity"]objectForKey:@"name"];
        
        ActionTableViewCell *someCell = (ActionTableViewCell *)[tableView dequeueReusableCellWithIdentifier:[ActionTableViewCell reuseIdentifier]];
        if (!someCell) {
            someCell = [[ActionTableViewCell alloc]initWithStyle:(UITableViewCellStyleDefault) reuseIdentifier: [ActionTableViewCell reuseIdentifier]];
        }
        if (someCell) {
            [someCell bind:[NSString stringWithFormat:@"%@ %@ call %@",from,[json objectForKey:@"action"],to]];
        }
        return someCell;
    }
    cell.textLabel.text = @"E R R O R";
    return cell;
}


#pragma mark - UITableViewDelegate

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{
    
    [UIView animateWithDuration:2.0f delay:0.0f usingSpringWithDamping:1 initialSpringVelocity:0.5 options:(UIViewAnimationOptionAllowUserInteraction) animations:^{
        cell.frame = CGRectMake(cell.frame.origin.x,cell.frame.origin.y - 10.0f , cell.frame.size.width, cell.frame.size.height);
    } completion:nil];
}
-(BOOL)tableView:(UITableView *)tableView shouldSpringLoadRowAtIndexPath:(NSIndexPath *)indexPath withContext:(id<UISpringLoadedInteractionContext>)context API_AVAILABLE(ios(11.0)){
    return YES;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
}
-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    
    BaseMessage *message = [messsagesArray objectAtIndex:[indexPath row]];
    
    if ([message isKindOfClass:TextMessage.class]) {
        
        TextMessage *textMessage = (TextMessage *)message;
        
        if ([[textMessage senderUid] isEqualToString:logged_in_user_uid]) {
            
            return CELL_ANIMATION_HEIGHT
            + [[[textMessage sender] name] getSize].height
            + [[textMessage text] getSize].height ;
        } else {
            
            return CELL_ANIMATION_HEIGHT
            + paddingY * 2
            + [[[textMessage sender] name] getSize].height
            + [[textMessage text] getSize].height ;
        }
        
    }else if ([message isKindOfClass:MediaMessage.class]){
        
        if (message.messageType == MessageTypeFile) {
            
            if ([[message senderUid] isEqualToString:logged_in_user_uid]) {
                
                CGFloat width = self.view.frame.size.width *0.40;
                return width*0.40f;
                
            } else {
                
                if ([message receiverType] == ReceiverTypeUser) {
                    
                    CGFloat width = self.view.frame.size.width *40/100;
                    return width*0.40f;
                } else {
                    
                    CGFloat width = self.view.frame.size.width *40/100;
                    return width*0.40f + paddingY*2;
                }
            }
            
            
        }else if (message.messageType == MessageTypeVideo || message.messageType == MessageTypeImage){
            
            if ([[message senderUid] isEqualToString:logged_in_user_uid]) {
                
                CGFloat width = self.view.frame.size.width *0.50;
                CGFloat height = width/0.75;
                return height;
                
            } else {
                
                if ([message receiverType] == ReceiverTypeUser) {
                    CGFloat width = self.view.frame.size.width *0.66;
                    CGFloat height = width/0.75;
                    return  height;
                } else {
                    CGFloat width = self.view.frame.size.width *0.66;
                    CGFloat height = width/0.75;
                    return paddingY*2 + height; // added height for sender name
                }
            }
            
            
        } else if (message.messageType == MessageTypeAudio){
            
            if ([[message senderUid] isEqualToString:logged_in_user_uid]) {
                
                CGFloat width = self.view.frame.size.width *0.40;
                return width*0.40f;
                
            } else {
                
                if ([message receiverType] == ReceiverTypeUser) {
                    
                    CGFloat width = self.view.frame.size.width *40/100;
                    return width*0.40f;
                } else {
                    
                    CGFloat width = self.view.frame.size.width *40/100;
                    return width*0.40f + paddingY*2;
                }
            }
        }
    }else if ([message isKindOfClass:ActionMessage.class]){
        
        ActionMessage *action = (ActionMessage *)message;
        CGSize sizeOfText = [[action message] getSize];
        return sizeOfText.height + paddingY*2;
    }else if ([message isKindOfClass:Call.class]){
        
        CGFloat width = self.view.frame.size.width *0.20;
        CGFloat height = width/2;
        return height + paddingX*2;
    }
    
    return 0.0f;
    
}
// identify links to made clickable
- (void)handleTapOnLabel:(UITapGestureRecognizer *)tapGesture
{
    
    UILabel *msgLabel = (UILabel *)tapGesture.view;
    NSString *textString = msgLabel.text;
    
    // Create instances of NSLayoutManager, NSTextContainer and NSTextStorage
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
    NSTextContainer *textContainer = [[NSTextContainer alloc] initWithSize:CGSizeZero];
    NSTextStorage *textStorage = [[NSTextStorage alloc] initWithString:textString];
    
    // Configure layoutManager and textStorage
    [layoutManager addTextContainer:textContainer];
    [textStorage addLayoutManager:layoutManager];
    
    // Configure textContainer
    textContainer.lineFragmentPadding = 0.0;
    textContainer.lineBreakMode = msgLabel.lineBreakMode;
    textContainer.maximumNumberOfLines = msgLabel.numberOfLines;
    textContainer.size = msgLabel.bounds.size;
    
    
    CGPoint locationOfTouchInLabel = [tapGesture locationInView:tapGesture.view];
    CGSize labelSize = tapGesture.view.bounds.size;
    CGRect textBoundingBox = [layoutManager usedRectForTextContainer:textContainer];
    CGPoint textContainerOffset = CGPointMake((labelSize.width - textBoundingBox.size.width) * 0.5 - textBoundingBox.origin.x,
                                              (labelSize.height - textBoundingBox.size.height) * 0.5 - textBoundingBox.origin.y);
    CGPoint locationOfTouchInTextContainer = CGPointMake(locationOfTouchInLabel.x - textContainerOffset.x,
                                                         locationOfTouchInLabel.y - textContainerOffset.y);
    NSInteger indexOfCharacter = [layoutManager characterIndexForPoint:locationOfTouchInTextContainer
                                                       inTextContainer:textContainer
                              fractionOfDistanceBetweenInsertionPoints:nil];
    NSArray *matches = [self getLinksArrayFromString:textString];
    
    if ([matches count]) {
        for (NSTextCheckingResult *match in matches) {
            NSRange matchRange = [match range];
            if ([match resultType] == NSTextCheckingTypeLink) {
                if (NSLocationInRange(indexOfCharacter, matchRange)) {
                    [[UIApplication sharedApplication] openURL:[match URL]];
                }
                
            }
        }
    }
    
    layoutManager = nil;
    textContainer = nil;
    textStorage = nil;
}
- (NSArray *)getLinksArrayFromString : (NSString *)string {
    
    NSDataDetector *detect = [[NSDataDetector alloc] initWithTypes:NSTextCheckingTypeLink error:nil];
    NSArray *matches = [detect matchesInString:string options:0 range:NSMakeRange(0, [string length])];
    return matches;
}
-(void) copy:(id)sender{
    
    BaseMessage *message = [messsagesArray objectAtIndex:0];
    
    if ([message isKindOfClass:TextMessage.class]) {
        
        TextMessage *textMessage = (TextMessage *)message;
        [UIPasteboard generalPasteboard].string = [textMessage text];
    }
}
#pragma mark - keyboard movements

-(void)dismissKeyboard
{
    [_sendMessageTextView resignFirstResponder];
}

- (void)keyboardWillChange:(NSNotification *)notification
{
    
    // Get duration of keyboard appearance/ disappearance animation
    UIViewAnimationCurve animationCurve = [[[notification userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];
    UIViewAnimationOptions animationOptions = animationCurve | (animationCurve << 16); // Convert animation curve to animation option
    NSTimeInterval animationDuration = [[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    // Get the final size of the keyboard
    CGRect keyboardEndFrame = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    
    // Calculate the new bottom constraint, which is equal to the size of the keyboard
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat newBottomConstraint = (screen.size.height-keyboardEndFrame.origin.y);
    
    // Keep old y content offset and height before they change
    CGFloat oldYContentOffset = self._tableView.contentOffset.y;
    CGFloat oldTableViewHeight = self._tableView.bounds.size.height;
    
    [UIView animateWithDuration:animationDuration delay:0 options:animationOptions animations:^{
        // Set the new bottom constraint
        self.wrapperBottomConstraint.constant = - newBottomConstraint;
        // Request layout with the new bottom constraint
        [self.view layoutIfNeeded];
        
        // Calculate the new y content offset
        CGFloat newTableViewHeight = self._tableView.bounds.size.height;
        CGFloat contentSizeHeight = self._tableView.contentSize.height;
        CGFloat newYContentOffset = oldYContentOffset - newTableViewHeight + oldTableViewHeight;
        
        // Prevent new y content offset from exceeding max, i.e. the bottommost part of the UITableView
        CGFloat possibleBottommostYContentOffset = contentSizeHeight - newTableViewHeight;
        newYContentOffset = MIN(newYContentOffset, possibleBottommostYContentOffset);
        
        // Prevent new y content offset from exceeding min, i.e. the topmost part of the UITableView
        CGFloat possibleTopmostYContentOffset = 0;
        newYContentOffset = MAX(possibleTopmostYContentOffset, newYContentOffset);
        
        // Create new content offset
        CGPoint newTableViewContentOffset = CGPointMake(self._tableView.contentOffset.x, newYContentOffset);
        self._tableView.contentOffset = newTableViewContentOffset;
        
    } completion:nil];
}
#pragma UITextViewDelegate

-(BOOL)textViewShouldBeginEditing:(UITextView *)textView{
    
    if (![textView.text isEqualToString:@""]) {
        _placeholderLabel.hidden = YES;
    }
    return YES;
}
-(void)textViewDidEndEditing:(UITextView *)textView{
    
    if ([textView.text isEqualToString:@""]) {
        _placeholderLabel.hidden = NO;
    }
    
    TypingIndicator *endTying = [[TypingIndicator alloc]initWithReceiverID:[_chatEntity receiverId] receiverType: [_chatEntity receiverType]];
    [CometChat endTypingWithIndicator:endTying];
    
}
-(BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ([text isEqualToString:@"\n"]) {
        NSString *message = _sendMessageTextView.text;
        if (![message isEqualToString:@""]) {
            
            message = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            [_sendMessageTextView setText:@""];
            _sendMessageHeightConstraint.constant = textFiledHeight;
            [_sendMessageTextView layoutIfNeeded];
            [_sendMessageTextView setNeedsUpdateConstraints];
            [_wrapperView layoutIfNeeded];
            [_wrapperView setNeedsUpdateConstraints];
            [_placeholderLabel setHidden:NO];
            [self sendMessage:message];
        }
    }
    return YES;
}
-(void)textViewDidChange:(UITextView *)textView{
    
    
    if (![textView.text isEqualToString:@""]) {
        _placeholderLabel.hidden = YES;
    }
    else {
        _placeholderLabel.hidden = NO;
    }
    
    
    float numberOfLines = (textView.contentSize.height - textView.textContainerInset.top - textView.textContainerInset.bottom) / textView.font.lineHeight;
    
    int n = numberOfLines;
    if (n == 1) {
        
        _sendMessageHeightConstraint.constant = textFiledHeight;
        _wrapperHeightConstraint.constant = 54.0f;
        [_wrapperView layoutIfNeeded];
        [_wrapperView setNeedsUpdateConstraints];
        [_sendMessageTextView layoutIfNeeded];
        [_sendMessageTextView setNeedsUpdateConstraints];
    }
    if (n == 2) {
        
        
        _sendMessageHeightConstraint.constant = 55.0f;
        _wrapperHeightConstraint.constant = 78.0f;
        [_wrapperView layoutIfNeeded];
        [_wrapperView setNeedsUpdateConstraints];
        [_sendMessageTextView layoutIfNeeded];
        [_sendMessageTextView setNeedsUpdateConstraints];
        
    }else if (n > 2) {
        _sendMessageHeightConstraint.constant = 85.0f;
        _wrapperHeightConstraint.constant = 95.0f;
        [_wrapperView layoutIfNeeded];
        [_wrapperView setNeedsUpdateConstraints];
        [_sendMessageTextView layoutIfNeeded];
        [_sendMessageTextView setNeedsUpdateConstraints];
    }
    TypingIndicator *sendTyping = [[TypingIndicator alloc]initWithReceiverID:[_chatEntity receiverId] receiverType: [_chatEntity receiverType]];
    [CometChat startTypingWithIndicator:sendTyping];
}
- (IBAction)sendBtnPressed:(UIButton *)sender {
    
    NSString *message = _sendMessageTextView.text;
    if (![message isEqualToString:@""]) {
        
        message = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [_sendMessageTextView setText:@""];
        _sendMessageHeightConstraint.constant = textFiledHeight;
        [_sendMessageTextView layoutIfNeeded];
        [_sendMessageTextView setNeedsUpdateConstraints];
        [_wrapperView layoutIfNeeded];
        [_wrapperView setNeedsUpdateConstraints];
        [_placeholderLabel setHidden:NO];
        [self sendMessage:message];
    }
}
- (IBAction)attachmentBtnPressed:(UIButton *)sender {
    
    
    UIAlertController *attachmentAlert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:(UIAlertControllerStyleActionSheet)];
    
    UIAlertAction * sendCameraPics = [UIAlertAction actionWithTitle:NSLocalizedString(@"Take Photo", @"") style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        
        [Camera PresentMultiCamera:self canEdit:YES];
    }];
    
    UIAlertAction *photosAndVideos = [UIAlertAction actionWithTitle:NSLocalizedString(@"Choose From Library", @"") style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        
        [Camera PresentPhotoLibrary:self canEdit:YES];
    }];
    
    UIAlertAction * sendDocuments = [UIAlertAction actionWithTitle:NSLocalizedString(@"Documents", @"") style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        
        [self selectDocument];
    }];
    UIAlertAction * recordAudio = [UIAlertAction actionWithTitle:NSLocalizedString(@"Audio recording", @"") style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
        
        [self recordAudio];
    }];
    
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:(UIAlertActionStyleCancel) handler:nil];
    
    [sendCameraPics setValue:[UIImage imageNamed:@"chat_camera"] forKey:@"image"];
    [photosAndVideos setValue:[UIImage imageNamed:@"chat_picture"] forKey:@"image"];
    [sendDocuments setValue:[UIImage imageNamed:@"chat_file"] forKey:@"image"];
    [recordAudio setValue:[UIImage imageNamed:@"chat_audio"] forKey:@"image"];
    
    [attachmentAlert addAction:sendCameraPics];
    [attachmentAlert addAction:sendDocuments];
    [attachmentAlert addAction:recordAudio];
    [attachmentAlert addAction:photosAndVideos];
    [attachmentAlert addAction:cancel];
    
    if(UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPhone)
        [self presentViewController:attachmentAlert
                           animated:YES completion:nil];
    else
    {
        _popover = attachmentAlert.popoverPresentationController;
        attachmentAlert.popoverPresentationController.sourceRect = _attachmentBtn.frame;
        attachmentAlert.popoverPresentationController.sourceView = _attachmentBtn;
        _popover.permittedArrowDirections = UIPopoverArrowDirectionDown;
        _popover.delegate = self;
        [self presentViewController:attachmentAlert
                           animated:YES completion:nil];
    }
    
    
}
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller traitCollection:(UITraitCollection *)traitCollection {
    return UIModalPresentationPopover;
}

- (UIViewController *)presentationController:(UIPresentationController *)controller viewControllerForAdaptivePresentationStyle:(UIModalPresentationStyle)style {
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller.presentedViewController];
    return navController;
}

-(void)selectDocument
{
    
    _documentPicker = [[UIDocumentPickerViewController alloc]initWithDocumentTypes:@[@publicContent]
                                                                            inMode:UIDocumentPickerModeImport];
    
    _documentPicker.delegate = self;
    _documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:_documentPicker animated:YES completion:nil];
}
-(void)recordAudio
{
    
    CGFloat margin = 8.0F;
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"\n\n\n\n\n\n" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    audioVisualizerView = [[AudioVisualizerView alloc]initWithFrame:CGRectMake(margin, margin, alertController.view.bounds.size.width - margin * 4.0F, 130.0f)];
    audioVisualizerView.delegate = self;
    [alertController.view addSubview:audioVisualizerView];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {}];
    [alertController addAction:cancelAction];
    [self presentViewController:alertController animated:YES completion:^{}];
}

#pragma mark - UIImagePickerController Delegate

-(void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:nil];
}
-(void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info
{
    
    if (@available(iOS 11.0, *)) {
        NSLog(@"%@ and %@ ",[[info objectForKey:UIImagePickerControllerMediaURL]absoluteString] , [info objectForKey:UIImagePickerControllerMediaType]);
    } else {
        // Fallback on earlier versions
    }
    
    MessageType messageType  = MessageTypeImage;
    NSString *filePath;
    
    if ([[info objectForKey:UIImagePickerControllerMediaType] isEqualToString:@publicMovie]) {
        
        messageType = MessageTypeVideo;
        filePath = [[info objectForKey:UIImagePickerControllerMediaURL]absoluteString];
        
    } else if ([[info objectForKey:UIImagePickerControllerMediaType] isEqualToString:@publicImage]){
        
        messageType = MessageTypeImage;
        if (@available(iOS 11.0, *)) {
            filePath = [[info objectForKey:UIImagePickerControllerImageURL]absoluteString];
        } else {
            // Fallback on earlier versions
        }
    }
    
    if (@available(iOS 11.0, *)) {
        
        MediaMessage *message = [[MediaMessage alloc]initWithReceiverUid:[_chatEntity receiverId]
                                                                 fileurl:filePath
                                                             messageType:messageType
                                                            receiverType:[_chatEntity receiverType]];
        
        [CometChat sendMediaMessageWithMessage:message onSuccess:^(MediaMessage * sent_message) {
            
            [messsagesArray addObject:sent_message];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                if ([messsagesArray count]) {
                    
                    [__tableView reloadData];
                    [__tableView scrollToBottom];
                }
            });
            
        } onError:^(CometChatException * error) {
            
            NSLog(@"Error %@",[error errorDescription]);
            
        }];
    } else {
        // Fallback on earlier versions
    }
    
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

-(void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller{
    
}
-(void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url{
    
    
    MediaMessage *fileMessage = [[MediaMessage alloc]initWithReceiverUid:_chatEntity.receiverId fileurl:url.absoluteString messageType:MessageTypeFile receiverType:_chatEntity.receiverType];
    
    [fileMessage setMetaData:[NSDictionary dictionaryWithObjectsAndKeys:[url lastPathComponent],@"fileName",nil]];
    
    [CometChat sendMediaMessageWithMessage:fileMessage onSuccess:^(MediaMessage * sent_message) {
        
        
        NSLog(@"asdad %@",[sent_message stringValue]);
        
        [messsagesArray addObject:sent_message];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if ([messsagesArray count]) {
                
                [__tableView reloadData];
                [__tableView scrollToBottom];
            }
        });
        
    } onError:^(CometChatException * error) {
        
        NSLog(@"Error %@",[error errorDescription]);
        
    }];
}

-(void)sendMessage:(NSString*)originalMessage
{
    
    TextMessage *message = [[TextMessage alloc]initWithReceiverUid:[_chatEntity receiverId] text:originalMessage messageType:MessageTypeText receiverType:[_chatEntity receiverType]];
    
    
    [CometChat sendTextMessageWithMessage:message onSuccess:^(TextMessage * sent_message) {
        
        
        NSLog(@"sent message %@",[sent_message stringValue]);
        
        [messsagesArray addObject:sent_message];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if ([messsagesArray count]) {
                
                [__tableView beginUpdates];
                NSArray *paths = [NSArray arrayWithObject:[NSIndexPath indexPathForRow:[messsagesArray count]-1 inSection:0]];
                [__tableView insertRowsAtIndexPaths:paths withRowAnimation:(UITableViewRowAnimationRight)];
                [__tableView endUpdates];
                [__tableView scrollToBottom];
            }
        });
        
    } onError:^(CometChatException * error) {
        
        NSLog(@"Error Sending Text Messages %@",[error errorDescription]);
        
    }];
    
    message = nil;
}
- (void)applicationdidReceiveNewMessage:(BaseMessage *)message {
    
    if ([appEntity isKindOfClass:User.class]) {
        
        User *user = (User *)appEntity;
        
        if ([[message senderUid] isEqualToString:[user uid]] && [message receiverType] == ReceiverTypeUser) {
            [messsagesArray addObject:message];
            
            if ([messsagesArray count]) {
                
                [__tableView beginUpdates];
                NSArray *paths = [NSArray arrayWithObject:[NSIndexPath indexPathForRow:[messsagesArray count]-1 inSection:0]];
                [__tableView insertRowsAtIndexPaths:paths withRowAnimation:(UITableViewRowAnimationAutomatic)];
                [__tableView endUpdates];
                [__tableView scrollToBottom];
                [CometChat markMessageAsReadWithMessage:message];
            }
            
        }
    } else if ([appEntity isKindOfClass:Group.class]) {
        
        Group *group = (Group *)appEntity;
        if ([[message receiverUid] isEqualToString:[group guid]]) {
            
            [messsagesArray addObject:message];
            if ([messsagesArray count]) {
                
                [__tableView beginUpdates];
                NSArray *paths = [NSArray arrayWithObject:[NSIndexPath indexPathForRow:[messsagesArray count]-1 inSection:0]];
                [__tableView insertRowsAtIndexPaths:paths withRowAnimation:(UITableViewRowAnimationAutomatic)];
                [__tableView endUpdates];
                [__tableView scrollToBottom];
                [CometChat markMessageAsReadWithMessage:message];
            }
        }
    }
    
    
}

-(void)applicationDidReceivedisTypingEvent:(TypingIndicator *)typingIndicator isComposing:(BOOL)isComposing
{
    NSLog(isComposing ? @"YES" : @"NO");
    NSLog(@"typingIndicator %@",[typingIndicator stringValue]);
    
    if ([[[typingIndicator sender] uid] isEqualToString:[_chatEntity receiverId]]) {
        if (isComposing) {
            UIView *new = [self naviagtionTitle:[_chatEntity receiverName] WithStatus:@"Typing.."];
            [self.navigationItem setTitleView:new];
        } else {
            
            NSString *lastActiveAt = [NSString stringWithFormat:@"%f",[[typingIndicator sender] lastActiveAt]];
            UIView *new = [self naviagtionTitle:[_chatEntity receiverName] WithStatus:[lastActiveAt sentAtToTime]];
            [self.navigationItem setTitleView:new];
        }
    }
}

- (void)applicationDidReceivedReadAndDeliveryReceipts:(MessageReceipt *)receipts {
    
    if ([[[receipts sender] uid] isEqualToString:[_chatEntity receiverId]]){
        
        NSPredicate *findMessage = [NSPredicate predicateWithBlock: ^BOOL(BaseMessage* obj, NSDictionary *bind){
            return  obj.id == [[receipts messageId] integerValue];
        }];
        
        NSArray <BaseMessage *> *messages = [messsagesArray filteredArrayUsingPredicate: findMessage];
        if ([messages count] == 1) {
            
            BaseMessage *originalMessage = [messsagesArray objectAtIndex:[messsagesArray indexOfObject:[messages objectAtIndex:0]]];
            BaseMessage *original = [messsagesArray objectAtIndex:[messsagesArray indexOfObject:[messages objectAtIndex:0]]];
            switch ([receipts receiptType])
            {
                    
                case ReceiptTypeDelivered:
                    originalMessage.deliveredAt = [receipts timeStamp];
                    break;
                case ReceiptTypeRead:
                    originalMessage.readAt = [receipts timeStamp];
                    break;
            }
            
            [messsagesArray replaceObjectAtIndex:[messsagesArray indexOfObject:original] withObject:originalMessage];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [__tableView beginUpdates];
                NSArray *paths = [NSArray arrayWithObject:[NSIndexPath indexPathForRow:[messsagesArray count]-1 inSection:0]];
                [__tableView reloadRowsAtIndexPaths:paths withRowAnimation:(UITableViewRowAnimationNone)];
                [__tableView endUpdates];
            });
        }
    }
}
-(void)showInfo
{
    
    InfoPageViewController *infoPage = [InfoPageViewController new];
    infoPage.hidesBottomBarWhenPushed = YES;
    infoPage.appEntity = [_chatEntity entity];
    [self.navigationController pushViewController:infoPage animated:YES];
    
}
#pragma mark - Dealloc

- (void)dealloc
{
    NSLog(@"dealloc %@", self);
}

#pragma mark - Memory Warning

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
-(UIImage *)loadThumbNail:(NSURL *)urlVideo
{
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:urlVideo options:nil];
    AVAssetImageGenerator *generate = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generate.appliesPreferredTrackTransform=TRUE;
    NSError *err = NULL;
    CMTime time = CMTimeMake(1, 60);
    CGImageRef imgRef = [generate copyCGImageAtTime:time actualTime:NULL error:&err];
    NSLog(@"err==%@, imageRef==%@", err, imgRef);
    return [[UIImage alloc] initWithCGImage:imgRef];
}
- (void)showMainImage:(UIGestureRecognizer*)gesture{
    
    MediaMessage *message = (MediaMessage*)[messsagesArray objectAtIndex:gesture.view.tag];
    previewUrl = [NSString stringWithFormat:@"%@",[message url]];
    [self showMediaForIndexPath];
    
}
-(void)showMediaForIndexPath{
    
    QLPreviewController *qlController = [[QLPreviewController alloc] init];
    [qlController setDataSource:self];
    [qlController setCurrentPreviewItemIndex:1];
    [[self navigationController] pushViewController:qlController animated:YES];
    
}
- (NSDictionary *)getNameAndExtentionFromURL:(NSString *)url {
    
    NSRange range1 = [url rangeOfString:@"/" options:NSBackwardsSearch];
    NSRange range2 = [url rangeOfString:@"." options:NSBackwardsSearch];
    if (range1.location != NSNotFound && range2.location != NSNotFound) {
        
        NSString *filename = [url substringWithRange:NSMakeRange(range1.location + range1.length, range2.location - range1.location - range1.length)];
        NSString *extention = [url substringFromIndex:range2.location];
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:filename, @"filename", extention, @"extention", nil];
        return dict;
        
    }else {
        
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:@"", @"filename", @"", @"extention", nil];
        return dict;
    }
}
- (NSInteger)numberOfPreviewItemsInPreviewController:(nonnull QLPreviewController *)controller {
    
    return 1;
    
}

- (nonnull id<QLPreviewItem>)previewController:(nonnull QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    
    if (![[NSFileManager defaultManager]fileExistsAtPath:[NSString stringWithFormat:@"%@/%@",[self documentsPath],[self fileNameWithExtentionforURL:previewUrl]]]) {
        
        NSData *fileData = [NSData dataWithContentsOfURL:[NSURL URLWithString:previewUrl]];
        
        [self fileData:fileData WriteToFile:[NSString stringWithFormat:@"%@/%@",[self documentsPath],[self fileNameWithExtentionforURL:previewUrl]] Automically:YES];
        
    }
    
    return [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@",[self documentsPath],[self fileNameWithExtentionforURL:previewUrl]]];
}
-(void)fileData:(NSData*)data WriteToFile:(NSString*)path Automically:(BOOL)isAutomically
{
    [data writeToFile:path atomically:isAutomically];
    UIImageWriteToSavedPhotosAlbum([UIImage imageWithData:data], nil, nil, nil);
    
}
-(NSString *)documentsPath{
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains (NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = [paths objectAtIndex:0];
    return documentsPath;
}
-(NSString *)fileNameWithExtentionforURL:(NSString*)string{
    
    NSDictionary *nameAndExt = [self getNameAndExtentionFromURL:string];
    NSString *fileNameWithExtention = [NSString stringWithFormat:@"%@%@",[nameAndExt objectForKey:@"filename"],[nameAndExt objectForKey:@"extention"]];
    return fileNameWithExtention;
}
- (void)applicationdidRecordNewAudioWithURL:(nonnull NSURL *)audioPath {
    
    MediaMessage *audioMessage = [[MediaMessage alloc]initWithReceiverUid:_chatEntity.receiverId fileurl:audioPath.absoluteString messageType:MessageTypeAudio receiverType:_chatEntity.receiverType];
    
    [CometChat sendMediaMessageWithMessage:audioMessage onSuccess:^(MediaMessage * sent_message) {
        
        [messsagesArray addObject:sent_message];
        
        NSLog(@"%@",[sent_message stringValue]);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if ([messsagesArray count]) {
                
                [__tableView beginUpdates];
                NSArray *paths = [NSArray arrayWithObject:[NSIndexPath indexPathForRow:[messsagesArray count]-1 inSection:0]];
                [__tableView insertRowsAtIndexPaths:paths withRowAnimation:(UITableViewRowAnimationRight)];
                [__tableView endUpdates];
                [__tableView scrollToBottom];
            }
        });
        
    } onError:^(CometChatException * error) {
        
        NSLog(@"Error %@",[error errorDescription]);
        
    }];
    if ([self presentingViewController]) {
        
        [self dismissViewControllerAnimated:[self presentingViewController] completion:nil];
    }
}
#pragma mark -
- (IBAction)playPauseButtonPressed:(UIButton *)sender
{
    
    BaseMessage *message = [messsagesArray objectAtIndex:[sender tag]];
    if ([message isKindOfClass:MediaMessage.class]) {
        
        MediaMessage *mediaMessage = (MediaMessage *)message;
        
        if (message.messageType == MessageTypeAudio) {
            
            previewUrl = [mediaMessage url];
            [self showMediaForIndexPath];
            
        }
    }
}

-(void)applicationDidReceiveUserEvent:(User *)user
{
    
    if ([[user uid]isEqualToString:[_chatEntity receiverId]]) {
        
        switch ([user status]) {
                
            case UserStatusOnline:
            {
                UIView *new = [self naviagtionTitle:[_chatEntity receiverName] WithStatus:@"Online"];
                [self.navigationItem setTitleView:new];
            }
                break;
            case UserStatusOffline:
            {
                UIView *new = [self naviagtionTitle:[_chatEntity receiverName] WithStatus:@"Offline"];
                [self.navigationItem setTitleView:new];
            }
                break;
        }
    }
}
/*pop up Animation*/
-(void)addPopUpAnimationToView:(UIView*)aView{
    
    [UIView animateWithDuration:0.3/1.5 animations:^{
        aView.transform = CGAffineTransformScale(CGAffineTransformIdentity, 1.1, 1.1);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3/2 animations:^{
            aView.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.9, 0.9);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.3/2 animations:^{
                aView.transform = CGAffineTransformIdentity;
            }];
        }];
    }];
}

- (void)didSelectMediaAtIndexPath:(NSInteger)tag
{
    [self openMediaWithTag:tag];
}

- (void)didSelectFileAtIndexPath:(NSInteger)tag
{
    [self openMediaWithTag:tag];
}
-(void)didSelectAudioAtIndexPath:(NSInteger)tag
{
    [self openMediaWithTag:tag];
}
-(void)openMediaWithTag:(NSInteger)tag
{
    MediaMessage *selctedMessage = (MediaMessage *)[messsagesArray objectAtIndex:tag];
    previewUrl = [selctedMessage url];
    [self showMediaForIndexPath];
}
-(UIView *)naviagtionTitle:(NSString *)name WithStatus:(NSString *)status
{
    
    
    UIView *titleView = [[UIView alloc]initWithFrame:CGRectMake(0.0f, 0.0f, self.navigationController.navigationBar.frame.size.width - 44.0f, self.navigationController.navigationBar.frame.size.height )];
    
    UILabel *nameLbl = [UILabel new];
    nameLbl.textColor = [UIColor whiteColor];
    [nameLbl setFont:[UIFont systemFontOfSize:14.0f weight:(UIFontWeightSemibold)]];
    nameLbl.textAlignment = NSTextAlignmentCenter;
    
    UILabel *statusLbl = [UILabel new];
    statusLbl.textColor = [UIColor whiteColor];
    [statusLbl setFont:[UIFont systemFontOfSize:12.0f]];
    statusLbl.textAlignment = NSTextAlignmentCenter;
    
    [titleView addSubview:nameLbl];
    [nameLbl setTranslatesAutoresizingMaskIntoConstraints:NO];
    [titleView addSubview:statusLbl];
    [statusLbl setTranslatesAutoresizingMaskIntoConstraints:NO];
    
    NSDictionary *views = NSDictionaryOfVariableBindings(nameLbl,statusLbl);
    
    NSArray *h1 = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[nameLbl]|" options:0 metrics:nil views:views];
    NSArray *h2 = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[statusLbl]|" options:0 metrics:nil views:views];
    NSArray *v = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[nameLbl][statusLbl]|" options:0 metrics:nil views:views];
    
    [titleView addConstraints:h1];
    [titleView addConstraints:h2];
    [titleView addConstraints:v];
    
    
    nameLbl.text = name;
    statusLbl.text = status;
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(showInfo)];
    [tap setNumberOfTapsRequired:1];
    [titleView addGestureRecognizer:tap];
    
    return titleView;
}
@end
