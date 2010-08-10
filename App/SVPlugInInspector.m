//
//  SVPlugInInspector.m
//  Sandvox
//
//  Created by Mike on 30/12/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "SVPlugInInspector.h"

#import "KSCollectionController.h"
#import "SVInspectorViewController.h"
#import "SVPlugIn.h"

#import "NSArrayController+Karelia.h"
#import "NSObject+Karelia.h"


static NSString *sPlugInInspectorInspectedObjectsObservation = @"PlugInInspectorInspectedObjectsObservation";


@interface SVPlugInInspector ()
@end


#pragma mark -


@implementation SVPlugInInspector

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    
    _plugInInspectors = [[NSMutableDictionary alloc] init];
    
    [self addObserver:self
           forKeyPath:@"inspectedObjectsController.selectedObjects"
              options:NSKeyValueObservingOptionOld
              context:sPlugInInspectorInspectedObjectsObservation];
    
    return self;
}
     
- (void)dealloc
{
    [self removeObserver:self forKeyPath:@"inspectedObjectsController.selectedObjects"];
    
    [_plugInInspectors release];
    
    [super dealloc];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)
change context:(void *)context
{
    if (context == sPlugInInspectorInspectedObjectsObservation)
    {
        NSString *identifier = [[self inspectedObjectsController] ks_valueForKeyPath:@"selection.plugInIdentifier"
                                                          raisesForNotApplicableKeys:NO];
        
        SVInspectorViewController *inspector = nil;
        if (NSIsControllerMarker(identifier))
        {
            identifier = nil;
        }
        else if (identifier)
        {
            inspector = [_plugInInspectors objectForKey:identifier];
            
            if (!inspector)
            {
                Class class = [[self inspectedObjectsController] valueForKeyPath:@"selection.inspectorFactoryClass"];
                inspector = [class makeInspectorViewController];
                
                if (inspector) [_plugInInspectors setObject:inspector forKey:identifier];
            }
            
            // Give it the right content/selection
            NSArrayController *controller = [inspector inspectedObjectsController];
            NSArray *plugIns = [[self inspectedObjects] valueForKey:@"plugIn"];
            [controller setContent:plugIns];
            [controller selectAll];
        }
        
        [self setSelectedInspector:inspector];
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark -

@synthesize selectedInspector = _selectedInspector;
- (void)setSelectedInspector:(SVInspectorViewController *)inspector;
{
    if (inspector == [self selectedInspector]) return;
    
    
    // Remove old inspector
    [[_selectedInspector view] removeFromSuperview];
    [[_selectedInspector inspectedObjectsController] setContent:nil];
    
    
    // Store new
    [_selectedInspector release]; _selectedInspector = [inspector retain];
    
    
    // Setup new
    @try
    {
        NSView *view = [inspector view];    // make sure it's loaded before going further
        
        if (inspector)
        {
            CGFloat height = [inspector contentHeightForViewInInspector];
            if (height > [self contentHeightForViewInInspector])
            {
                [self setContentHeightForViewInInspector:height];
            }
        }
        
        [view setFrame:[[self view] frame]];
        [[self view] addSubview:view];
		
		[_selectedInspector setRepresentedObject:[self representedObject]];
    }
    @catch (NSException *exception)
    {
        // TODO: Log error
    }
}

@end
