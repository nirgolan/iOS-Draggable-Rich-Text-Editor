//
//  DraggableRichTextEditor.h
//  RichTextEditor
//
//  Created by Nir Golan on 1/2/16.
//  Copyright © 2016 Aryan Ghassemi. All rights reserved.
//

#import "RichTextEditor.h"
@class DraggableRichTextEditor;

@protocol DraggableRichTextDelegate <UITextViewDelegate>

-(void)draggableRichTextDidTap:(DraggableRichTextEditor*)textLabel;
-(void)draggableRichTextDidDoubleTap:(DraggableRichTextEditor*)textLabel;
-(void)draggableRichTextDidStartDragging:(DraggableRichTextEditor *)textLabel start:(BOOL)start;
@end

@interface DraggableRichTextEditor : RichTextEditor

@property (nonatomic, weak) id<DraggableRichTextDelegate> draggableDelegate;
@property BOOL wasEdited;
@property BOOL editInPlace;

-(void)updateBoundsForContentSize;
@end
