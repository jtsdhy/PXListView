//
//  PXListView.m
//  PXListView
//
//  Created by Alex Rozanski on 29/05/2010.
//  Copyright 2010 Alex Rozanski. http://perspx.com. All rights reserved.
//

#import "PXListView.h"

#import "PXListViewCell.h"
#import "PXListViewCell+Private.h"

@interface PXListView ()
- (void)cacheCellLayout;
- (void)layoutCells;
- (NSRect)viewportRect;
- (void)layoutCell:(PXListViewCell*)cell;
- (void)addCellsFromVisibleRange;
- (void)addNewVisibleCell:(PXListViewCell*)cell atRow:(NSInteger)row;
- (void)updateCells;
- (void)enqueueCell:(PXListViewCell*)cell;
@end


@implementation PXListView

@synthesize delegate = _delegate;
@synthesize cellSpacing = _cellSpacing;

#pragma mark -
#pragma mark Init/Dealloc

- (id)initWithCoder:(NSCoder*)decoder
{
	if(self = [super initWithCoder:decoder]) {
		_reusableCells = [[NSMutableArray alloc] init];
		_visibleCells = [[NSMutableArray alloc] init];
	}
	
	return self;
}

- (void)awakeFromNib
{
	//Subscribe to scrolling notification
	NSClipView *contentView = [self contentView];
	[contentView setPostsBoundsChangedNotifications:YES];
	
    [[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(contentViewBoundsDidChange:)
												 name:NSViewBoundsDidChangeNotification
											   object:contentView];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[_reusableCells release];
	[_visibleCells release];
	[super dealloc];
}

#pragma mark -
#pragma mark Data Handling

- (void)reloadData
{
	id <PXListViewDelegate> delegate = [self delegate];
	
	//Clean up cached resources
	[_reusableCells removeAllObjects];
	[_visibleCells removeAllObjects];
	free(_cellYOffsets);
	
	if([delegate conformsToProtocol:@protocol(PXListViewDelegate)])
	{
		_numberOfRows = [delegate numberOfRowsInListView:self];
		[self cacheCellLayout];
		
		NSRange visibleRange = [self visibleRange];
		_currentRange = visibleRange;
		[self addCellsFromVisibleRange];
		
		[self layoutCells];
	}
}

#pragma mark -
#pragma mark Cell Handling

- (PXListViewCell*)dequeueCellWithReusableIdentifier:(NSString*)identifier
{
	PXListViewCell *dequeuedCell = nil;
	
	for(id cell in _reusableCells) {
		if([[cell reusableIdentifier] isEqual:identifier]) {
			dequeuedCell = cell;
			break;
		}
	}
	
	[dequeuedCell retain];
	[_reusableCells removeObject:dequeuedCell];
	
	return [dequeuedCell autorelease];
}

- (PXListViewCell*)visibleCellForRow:(NSInteger)row
{
	for(id cell in _visibleCells) {
		if([cell row]==row) {
			return cell;
		}
	}
	
	return nil;
}

- (void)addCellsFromVisibleRange
{
	NSRange visibleRange = [self visibleRange];
	
	for(NSInteger i=visibleRange.location;i<NSMaxRange(visibleRange);i++) {
		id cell = [[self delegate] listView:self cellForRow:i];
		[_visibleCells addObject:cell];
		[self addNewVisibleCell:cell atRow:i];
	}
}

- (NSRange)visibleRange
{
	NSRect visibleRect = [[self contentView] documentVisibleRect];
	NSInteger startRange = -1;
	NSInteger endRange = -1;
	BOOL inRange = NO;
	
	for(NSInteger i=0;i<_numberOfRows;i++) {
		if(NSIntersectsRect([self rectOfRow:i], visibleRect)) {
			if(startRange==-1) {
				startRange = i;
				inRange = YES;
			}
		}
		else {
			if(inRange) {
				endRange = i;
				break;
			}
		}
	}
	
	if(endRange==-1) {
		endRange = _numberOfRows; 
	}
	
	NSRange visibleRange = NSMakeRange(startRange, endRange-startRange);
	
	/*if(visibleRange.location>0) {
		visibleRange.location--;
		visibleRange.length++;
	}
	if(NSMaxRange(visibleRange)<_numberOfRows) {
		visibleRange.length++;
	}*/
	
	return visibleRange;
}

- (void)updateCells
{	
	if(_inLiveResize) {
		return;
	}
	
	NSRange visibleRange = [self visibleRange];
	NSRange intersectionRange = NSIntersectionRange(visibleRange, _currentRange);
	
	if(visibleRange.location==_currentRange.location&&
	   NSMaxRange(visibleRange)==NSMaxRange(_currentRange)) {
		return;
	}
	
	if(intersectionRange.location==0&&intersectionRange.length==0) {
		//We'll have to rebuild all the cells
		[_reusableCells addObjectsFromArray:_visibleCells];
		[_visibleCells removeAllObjects];
		[[self documentView] setSubviews:[NSArray array]];
		[self addCellsFromVisibleRange];
	}
	else {
		if(visibleRange.location<_currentRange.location) { //Add top 
			for(NSInteger i=_currentRange.location;i>visibleRange.location;i--)
			{
				NSInteger newRow = i-1;
				PXListViewCell *cell = [[self delegate] listView:self cellForRow:newRow];
				[_visibleCells insertObject:cell atIndex:0];
				[self addNewVisibleCell:cell atRow:newRow];
			}
		}
		else if(visibleRange.location>_currentRange.location) { //Remove top
			for(NSInteger i=visibleRange.location;i>_currentRange.location;i--) {
				PXListViewCell *firstCell = [_visibleCells objectAtIndex:0];
				[self enqueueCell:firstCell];
			}
		}
		
		if(NSMaxRange(visibleRange)>NSMaxRange(_currentRange)) { //Add bottom
			for(NSInteger i=NSMaxRange(_currentRange);i<NSMaxRange(visibleRange);i++)
			{
				NSInteger newRow = i;
				PXListViewCell *cell = [[self delegate] listView:self cellForRow:newRow];
				[_visibleCells addObject:cell];
				[self addNewVisibleCell:cell atRow:newRow];
			}
		}
		else if(NSMaxRange(visibleRange)<NSMaxRange(_currentRange)) { //Remove bottom
			for(NSInteger i=NSMaxRange(_currentRange);i>NSMaxRange(visibleRange);i--) {
				PXListViewCell *lastCell = [_visibleCells lastObject];
				[self enqueueCell:lastCell];
			}
		}
	}
	
	NSLog(@"%d", [_visibleCells count]);
	
	_currentRange = visibleRange;
}

- (void)enqueueCell:(PXListViewCell*)cell
{
	[_reusableCells addObject:cell];
	[_visibleCells removeObject:cell];
	[cell removeFromSuperview];
}

- (void)addNewVisibleCell:(PXListViewCell*)cell atRow:(NSInteger)row
{
	[[self documentView] addSubview:cell];
	[cell setRow:row];
	[self layoutCell:cell];
}

#pragma mark -
#pragma mark Layout

- (NSRect)rectOfRow:(NSInteger)row
{
	if([[self delegate] conformsToProtocol:@protocol(PXListViewDelegate)]) {
		NSRect bounds = [self bounds];
		
		return NSMakeRect(0, _cellYOffsets[row], NSWidth(bounds), [[self delegate] listView:self heightOfRow:row]);
	}
	
	return NSZeroRect;
}

- (void)cacheCellLayout
{
	CGFloat totalHeight = 0;
	
	//Allocate the offset caching array
	_cellYOffsets = (CGFloat*)malloc(sizeof(CGFloat)*_numberOfRows);
	
	for(NSInteger i=0;i<_numberOfRows;i++) {
		_cellYOffsets[i] = totalHeight;
		CGFloat cellHeight = [[self delegate] listView:self heightOfRow:i];
		
		totalHeight+=cellHeight+[self cellSpacing];
	}
	
	_totalHeight = totalHeight;
	
	[[self documentView] setFrame:NSMakeRect(0, 0, NSWidth([self bounds]), _totalHeight)];
}

- (NSRect)viewportRect
{
	NSRect frame = [self frame];
	NSSize frameSize = NSMakeSize(NSWidth(frame), NSHeight(frame));
	BOOL hasVertScroller = NSHeight(frame)<_totalHeight;
	
	NSSize availableSize = [NSScrollView contentSizeForFrameSize:frameSize
										   hasHorizontalScroller:NO
											 hasVerticalScroller:hasVertScroller
													  borderType:[self borderType]];
	
	return NSMakeRect(0, 0, availableSize.width, availableSize.height);
}

- (void)layoutCells
{
	NSRect availableRect = [self viewportRect];
	
	//Set the frames of the cells
	for(id cell in _visibleCells) {
		NSInteger row = [cell row];
		CGFloat cellHeight = [[self delegate] listView:self heightOfRow:row];
		NSRect cellFrame = NSMakeRect(0, _cellYOffsets[row], NSWidth(availableRect), cellHeight);	
		[cell setFrame:cellFrame];
	}
}

- (void)layoutCell:(PXListViewCell*)cell
{
	NSRect availableRect = [self viewportRect];	
	
	NSInteger row = [cell row];
	CGFloat cellHeight = [[self delegate] listView:self heightOfRow:row];
	NSRect cellFrame = NSMakeRect(0, _cellYOffsets[row], NSWidth(availableRect), cellHeight);	
	[cell setFrame:cellFrame];
}

#pragma mark -
#pragma mark Sizing

- (void)viewWillStartLiveResize
{
	_inLiveResize = YES;
}

- (void)viewDidEndLiveResize
{
	[super viewDidEndLiveResize];
	
	//Change the layout of the cells
	[_visibleCells removeAllObjects];
	[[self documentView] setSubviews:[NSArray array]];

	[self cacheCellLayout];
	[self addCellsFromVisibleRange];
	
	_currentRange = [self visibleRange];
	
	NSLog(@"%d", [_visibleCells count]);
	
	_inLiveResize = NO;
}

#pragma mark -
#pragma mark Scrolling

- (void)contentViewBoundsDidChange:(NSNotification *)notification
{
	[self updateCells];
}

@end