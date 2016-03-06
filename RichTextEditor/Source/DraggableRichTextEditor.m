//
//  DraggableRichTextEditor.m
//  RichTextEditor
//
//  Created by Nir Golan on 1/2/16.
//  Copyright © 2016 Aryan Ghassemi. All rights reserved.
//

#import "DraggableRichTextEditor.h"

typedef enum {
    PinchAxisNone,
    PinchAxisHorizontal,
    PinchAxisVertical
} PinchAxis;

PinchAxis pinchGestureRecognizerAxis(UIPinchGestureRecognizer *r) {
    if (r.numberOfTouches < 2) {
        return PinchAxisNone;
    }
    
    UIView *view = r.view;
    CGPoint touch0 = [r locationOfTouch:0 inView:view];
    CGPoint touch1 = [r locationOfTouch:1 inView:view];
    CGFloat tangent = fabsf((touch1.y - touch0.y) / (touch1.x - touch0.x));
    return
    tangent <= 0.2679491924f ? PinchAxisHorizontal // 15 degrees
    : tangent >= 3.7320508076f ? PinchAxisVertical   // 75 degrees
    : PinchAxisNone;
}


@interface DraggableRichTextEditor () <UIGestureRecognizerDelegate , RichTextEditorDataSource>


@property (strong, nonatomic) UIPanGestureRecognizer* panRecognizer;
@property (strong, nonatomic) UIPinchGestureRecognizer* pinchRecognizer;
@property (strong, nonatomic) UIRotationGestureRecognizer* rotateRecognizer;
@property (strong, nonatomic) UITapGestureRecognizer* tapRecognizer;
@property (strong, nonatomic) UITapGestureRecognizer* doubleTapRecognizer;


@property (nonatomic) BOOL isDragging;
@property (atomic) BOOL fixingRotation;
@property (atomic) BOOL isSinking;
@property (atomic) int sinkCounter;
@property (atomic) int passedMaxVelocity;
@property (atomic) CGPoint lastTranslation;


@property (nonatomic) CGFloat viewRotation;
@property (nonatomic) CGPoint viewPanning;
@property (nonatomic) CGFloat viewScaling;

@property PinchAxis pinchAxis;

@property BOOL isCurrentlyEditing;

@end

#define RESPONSIVE_MIN_ImageView_WIDTH 200.0
#define VELOCITY_FOR_DELETE 150.0
#define kPointInsideCache 8
#define kSizeForAlpha 50.0
#define kDefaultFontSize 42.0
#define kMinimumFontSize 14.0

@implementation DraggableRichTextEditor

-(instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self commonInit];
    }
    
    return self;
}

-(instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

-(void)commonInit
{
    [self setupGestureRecognizers];
    [self setupDefaultStyle];
}

-(void)setupDefaultStyle
{
    self.font = [UIFont fontWithName:@"Avenir Next" size:kDefaultFontSize] ;

    self.borderColor = [UIColor clearColor];
    self.borderWidth = 1.0;
    
    self.dataSource= self;
}

-(void)setupGestureRecognizers
{
    self.panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panRecognized:)];
    self.pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchRecognized:)];
    self.rotateRecognizer = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(rotateRecognized:)];
    self.tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapRecognized:)];
    self.tapRecognizer.numberOfTapsRequired = 1;
    
    self.doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapRecognized:)];
    self.doubleTapRecognizer.numberOfTapsRequired = 2;
    
    _doubleTapRecognizer.delegate = _tapRecognizer.delegate =  _rotateRecognizer.delegate = _panRecognizer.delegate = _pinchRecognizer.delegate = self;
    
    [self.tapRecognizer requireGestureRecognizerToFail:self.doubleTapRecognizer];

    [self addGestureRecognizer:_panRecognizer];
    [self addGestureRecognizer:_rotateRecognizer];
    [self addGestureRecognizer:_pinchRecognizer];
    [self addGestureRecognizer:_tapRecognizer];
    [self addGestureRecognizer:_doubleTapRecognizer];
    
}


-(void)setIsDragging:(BOOL)isDragging
{
    BOOL changed = isDragging != _isDragging;
    if (changed) {
        _isDragging = isDragging;
        self.borderColor = isDragging ? [UIColor lightGrayColor] : [UIColor clearColor];
    }
}

-(void)updateBoundsForContentSize
{
    
    CGFloat maxWidth = self.superview.bounds.size.width * 0.9;

    CGFloat suggestedWidth = MIN(maxWidth, self.bounds.size.width);
    CGFloat suggestedHeight = self.contentSize.height;
    
    CGRect newRect = CGRectMake(0, 0, suggestedWidth , suggestedHeight);
    
    if ([self isRotatedOneRadian]) {
        newRect = CGRectMake(0, 0, suggestedHeight , suggestedWidth);
    }

    self.bounds = newRect;

}

-(BOOL)isRotatedOneRadian
{
    // return YES if width is height and vice versa
    // 45 deg - 135  , 225 - 315
    CGFloat rotation = self.viewRotation;
    CGFloat absRotation = fabs(180.0 - rotation);
    if (absRotation >= 45.0 && absRotation <= 135.0) {
        return YES;
    }
    
    return NO;
}

-(void)setAttributedText:(NSAttributedString *)attributedText
{
    [super setAttributedText:attributedText];
    
    [self textViewDidChange:self];
}

#pragma mark - text view delegate
-(BOOL)textViewShouldBeginEditing:(UITextView *)textView
{
    if (self.editInPlace) {
        return YES;
    } else {
        [self.draggableDelegate draggableRichTextDidTap:self];
    }
    
    
    return NO;
}

-(void)textViewDidBeginEditing:(UITextView *)textView
{
    self.isCurrentlyEditing = YES;
    
    
    // super is still the delegate
    if ([[self superclass] instancesRespondToSelector:@selector(textViewDidBeginEditing:)]) {
        
        [super textViewDidBeginEditing:textView];
    }
}

-(void)textViewDidEndEditing:(UITextView *)textView
{
    self.isCurrentlyEditing = NO;
    
    // super is still the delegate
    if ([[self superclass] instancesRespondToSelector:@selector(textViewDidEndEditing:)]) {
        [super textViewDidEndEditing:textView];
    }
}

-(BOOL)textViewShouldEndEditing:(UITextView *)textView
{
    if ([self.draggableDelegate respondsToSelector:@selector(textViewShouldEndEditing:)]) {
         return [self.draggableDelegate textViewShouldEndEditing:self];
    }

    return YES;
}

-(void)textViewDidChange:(UITextView *)textView
{
    // super is still the delegate
    if ([[self superclass] instancesRespondToSelector:@selector(textViewDidChange:)]) {
        [super textViewDidChange:textView];
    }
    
    if ([self.draggableDelegate respondsToSelector:@selector(textViewDidChange:)]) {
        [self.draggableDelegate textViewDidChange:self];
    }

}

-(BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange
{
    return NO;
}

-(BOOL)textView:(UITextView *)textView shouldInteractWithTextAttachment:(NSTextAttachment *)textAttachment inRange:(NSRange)characterRange
{
    return NO;
}

#pragma mark - increase font size

-(void)increaseFontSizeBy:(NSInteger)margin
{
    NSMutableAttributedString *res = [self.attributedText mutableCopy];
    
    [res beginEditing];
    __block BOOL found = NO;
    [res enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, res.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value) {
            UIFont *oldFont = (UIFont *)value;
            
            CGFloat newSize = oldFont.pointSize + margin;
            if (newSize < kMinimumFontSize) {
                newSize = kMinimumFontSize;
            }
            UIFont *newFont = [oldFont fontWithSize:newSize];
            [res removeAttribute:NSFontAttributeName range:range];
            [res addAttribute:NSFontAttributeName value:newFont range:range];
            found = YES;
        }
    }];
    if (!found) {
        // No font was found - do something else?
    }
    [res endEditing];
    self.attributedText = res;
}

#pragma mark - Data Source
-(NSArray *)fontSizeSelectionForRichTextEditor:(RichTextEditor *)richTextEditor
{

    return @[@16, @18, @20, @22, @24, @26, @28, @30, @32, @34 , @38, @42, @46, @50, @55, @60, @72];

}


- (RichTextEditorFeature)featuresEnabledForRichTextEditor:(RichTextEditor *)richTextEditor
{
    return RichTextEditorFeatureFontSize | RichTextEditorFeatureFont | RichTextEditorFeatureAll;
}


#pragma mark - gesture recognizers
- (void) gestureUpdated:(UIGestureRecognizer*)recognizer
{
    BOOL started = (recognizer.state == UIGestureRecognizerStateBegan) ;
    if (!started && recognizer.state == UIGestureRecognizerStateChanged)
        return;
    
    if (_isDragging && started) return;
    if (!_isDragging && !started) return;
    
    if (started) {
        
        [self setAndNotifyDragging:YES];
        
    } else {
        // check that other gesture recognizers are ended as well
        if ((_panRecognizer.state != UIGestureRecognizerStateBegan || _panRecognizer.state != UIGestureRecognizerStateChanged) &&
            (_pinchRecognizer.state != UIGestureRecognizerStateBegan || _pinchRecognizer.state != UIGestureRecognizerStateChanged) &&
            (_rotateRecognizer.state != UIGestureRecognizerStateBegan || _rotateRecognizer.state != UIGestureRecognizerStateChanged)) {
            
            [self setAndNotifyDragging:NO];
            
            [self updateBoundsForContentSize];
            
            [self setNeedsDisplay];
        }
    }
    
}

- (void)panRecognized:(UIPanGestureRecognizer*)recognizer
{
    if (self.isCurrentlyEditing) {
        return;
    }
    
    [self gestureUpdated:recognizer];
    
    
    CGPoint translation = [recognizer translationInView:self];
    if (translation.x != 0 || translation.y != 0)
        self.lastTranslation = translation;
    
    CGFloat length = sqrtf(translation.x * translation.x + translation.y * translation.y)  ;
    
    CGFloat deleteThreshold = VELOCITY_FOR_DELETE / (1.5 * _viewScaling);
    if (length > 30)
        NSLog(@"translate Velocity %.f , threshold %.2f", length , deleteThreshold );
    
    //NSLog(@"state = %d" ,recognizer.state);
    
    if (length > deleteThreshold  && recognizer.numberOfTouches == 1) {
        self.passedMaxVelocity = 7;
        
    } else {
        self.passedMaxVelocity--;
    }
    
    [recognizer.view.layer setAffineTransform:CGAffineTransformTranslate(recognizer.view.transform ,translation.x , translation.y)];
    
    //    recognizer.view.layer.position = CGPointMake(recognizer.view.center.x + translation.x,
    //                                         recognizer.view.center.y + translation.y);
    [recognizer setTranslation:CGPointMake(0, 0) inView:self];
    
    if (recognizer.state != UIGestureRecognizerStateChanged) {
     //   [self updateHighlight];
    }
    
    if (recognizer.state == UIGestureRecognizerStateEnded ||
        recognizer.state == UIGestureRecognizerStateCancelled ||
        recognizer.state == UIGestureRecognizerStateFailed) {
        // translate panning to actual view
        
        NSLog(@"origin %.2f , %.2f\n center %.2f %.2f" , self.frame.origin.x , self.frame.origin.y , self.center.x , self.center.y) ;
        
        if (self.passedMaxVelocity > 0) {
            
            [recognizer setTranslation:CGPointMake(0, 0) inView:self];
            if (self.isSinking) return;
            self.isSinking = YES;
            NSLog(@"calling throw animation with direction %.2f/%.2f" , self.lastTranslation.x , self.lastTranslation.y);
#warning fix
//            [self animateThrowAwayWithDirection: CGPointMake(self.lastTranslation.x > 0 ? 100 : -100, self.lastTranslation.y > 0 ? 100 : -100)];
//            
        }
        self.passedMaxVelocity = 0;
    }
}

- (void)rotateRecognized:(UIRotationGestureRecognizer*)recognizer
{
    if (self.isCurrentlyEditing) {
        return;
    }
    
    [self gestureUpdated:recognizer];
    
    CGFloat rotation =  recognizer.rotation ;
    
    [recognizer.view.layer setAffineTransform:CGAffineTransformRotate(recognizer.view.transform, rotation)];
    _viewRotation = (_viewRotation + (rotation * 180.0 / M_PI)) ;
    _viewRotation = (_viewRotation > 360.0 ? _viewRotation - 360.0 : _viewRotation);
    _viewRotation = (_viewRotation < -360.0 ? _viewRotation + 360.0 : _viewRotation);
    
    recognizer.rotation = 0;
    
    [self updateBoundsForContentSize];

    
    if (recognizer.state != UIGestureRecognizerStateChanged) {
//        [self updateHighlight];
    }
    
    // fix 10 degrees angles
    if ((recognizer.state == UIGestureRecognizerStateEnded ||
         recognizer.state == UIGestureRecognizerStateCancelled ||
         recognizer.state == UIGestureRecognizerStateFailed) && (_viewRotation > -8.0f && _viewRotation < 8.0f))
    {
        [self fixRotationCompletion:^{}];
    }
}

- (void)pinchRecognized:(UIPinchGestureRecognizer*)recognizer
{
    if (self.isCurrentlyEditing) {
        return;
    }
    
    [self gestureUpdated:recognizer];
    
    CGAffineTransform newTransform = CGAffineTransformScale(recognizer.view.transform, recognizer.scale, 1.0);
    
    CGFloat maxWidth = self.superview.bounds.size.width * 0.9;
    CGFloat updatedWidth = MIN(maxWidth, self.bounds.size.width * recognizer.scale);

    BOOL reachedMaxWidth = (maxWidth == updatedWidth);
    CGRect newRect = CGRectMake(0, 0, updatedWidth, self.contentSize.height);
    
    if ([self isRotatedOneRadian]) {
        newRect = CGRectMake(0, 0, newRect.size.height, newRect.size.width);
    }

    
    
    PinchAxis axis = pinchGestureRecognizerAxis(recognizer);
//    NSLog(@"pinchAxis %i , %f", axis, recognizer.scale);
    
    if (self.pinchAxis == PinchAxisNone) {
        self.pinchAxis = axis;
    }
    
    
    BOOL tooBig = NO;
    /*(newRect.size.width >= [[UIScreen mainScreen] bounds].size.height * 1.2||
     newRect.size.height >= [UIScreen mainScreen].bounds.size.width * 1.2);*/
    BOOL tooSmall = (newRect.size.width <= RESPONSIVE_MIN_ImageView_WIDTH);
    
    BOOL shouldResize = !(recognizer.scale > 1 && tooBig) // not too big
    && !(tooSmall) ;
    
    if (shouldResize) {
        
        if (self.pinchAxis == PinchAxisHorizontal && !reachedMaxWidth) {
            
            if (fabs(1.0 - recognizer.scale) > 0.02 && !tooSmall) {
                recognizer.view.bounds = newRect;
                
                self.viewScaling = self.viewScaling * recognizer.scale;
                recognizer.scale = 1.0;
                
                [self updateBoundsForContentSize];
            }
        } else {
            
            if (fabs(1.0 - recognizer.scale) > 0.05) {
                
                // increase/decrease font size
                [self increaseFontSizeBy:recognizer.scale > 1.0 ? 2.0 : -2.0];
                
                recognizer.scale = 1.0;
                [self updateBoundsForContentSize];
            }
            
        }
        
        if (recognizer.state != UIGestureRecognizerStateChanged) {
        }
        
    } else if (tooSmall) {
        
        // increase/decrease font size
        [self increaseFontSizeBy:recognizer.scale > 1.0 ? 1.0 : -1.0];
        
        recognizer.scale = 1.0;
        [self updateBoundsForContentSize];
        
    }
    
    if (recognizer.state == UIGestureRecognizerStateEnded ||
        recognizer.state == UIGestureRecognizerStateCancelled ||
        recognizer.state == UIGestureRecognizerStateFailed)
    {
        
        self.pinchAxis = PinchAxisNone;
    }
    
}

- (void)doubleTapRecognized:(UITapGestureRecognizer*)recognizer
{
    [self gestureUpdated:recognizer];
    
    if (self.isSinking){
        self.isSinking = NO;
        return;
    }
    
    
    if (recognizer == self.doubleTapRecognizer) {
        if ([self.draggableDelegate respondsToSelector:@selector(draggableRichTextDidDoubleTap:)])
            [self.draggableDelegate draggableRichTextDidDoubleTap:self];
    }
}

- (void)tapRecognized:(UITapGestureRecognizer*)recognizer
{
    [self gestureUpdated:recognizer];
    
    if (self.isSinking){
        self.isSinking = NO;
        return;
    }
    
    if (recognizer == self.tapRecognizer) {
        // single tap
        if ([self.draggableDelegate respondsToSelector:@selector(draggableRichTextDidTap:)])
            [self.draggableDelegate draggableRichTextDidTap:self];
    }
    
}

#pragma mark - Gesture delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    BOOL retVal = !(gestureRecognizer.class == [UITapGestureRecognizer class] ||
                    otherGestureRecognizer.class == [UITapGestureRecognizer class]);
    return retVal;
}

#pragma mark - touches - notify delegate
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
//    [self setAndNotifyDragging:YES];
    
    if (self.isSinking) {
        NSLog(@"sinking and touching");
        self.isSinking = NO;
    }
    
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    [self setAndNotifyDragging:NO];
}


- (void) setAndNotifyDragging:(BOOL)dragging
{
    if (dragging != self.isDragging) {
        
        self.isDragging = dragging;
    
        [self.draggableDelegate draggableRichTextDidStartDragging:self start:dragging];
        
    }
}

-(void)fixRotationCompletion:(void (^)(void))completionBlock
{
    
    if (self.fixingRotation) {
        completionBlock();
        return;
    }
    
    self.fixingRotation = YES;
    CGFloat rotation = _viewRotation;
    _viewRotation = 0.0;
    [UIView animateWithDuration:0.3 animations:^{
        [self.layer setAffineTransform:CGAffineTransformRotate(self.transform, -rotation * M_PI / 180.0)];
    } completion:^(BOOL finished) {
        self.fixingRotation = NO;
        completionBlock();
    }];
}



- (void)paste:(id)sender {
//    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
//    NSLog(@"types available: %@", [pasteboard pasteboardTypes]);
//    for (NSString *type in [pasteboard pasteboardTypes]) {
//        NSLog(@"type %@ (%@): %@", type, NSStringFromClass([[pasteboard valueForPasteboardType:type] class]), [pasteboard valueForPasteboardType:type]);
//    }
    
    [super paste:sender];
    
    // strip URLs from the text after pasting
    NSMutableAttributedString *attributedString = [self.attributedText mutableCopy];
    [attributedString removeAttribute:NSLinkAttributeName range:NSMakeRange(0, attributedString.length)];
    self.attributedText = attributedString;

}
@end
