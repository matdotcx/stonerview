//
//  StonerView.m
//  http://eblong.com/zarf/stonerview.html
//
//  Copyright 1998-2011 by Andrew Plotkin, <erkyrath@eblong.com>.
//  Ported to Mac by Tommaso Pecorella, <t.pecorella@inwind.it>.
//	Modified by Alexander von Below, <alex@vonbelow.com>
//      Wed Jul 11 10:09:26 CEST 2007 (Changes are prefixed 'avb')
//	Further modified by Andrew Plotkin, Mar 24 2011
//  Updated for BigSur (MacOSX 11) by Sriranga Veeraraghavan
//      <ranga@calalum.org>, May 16, 2021
//

#import "StonerView.h"
#include <unistd.h>
// Include forward declarations for oscillator functions
struct osc_t;
/* osc_t is already defined in osc.h */

extern osc_t *new_osc_linear(osc_t *arg1, osc_t *arg2);
extern osc_t *new_osc_velowrap(int min, int max, osc_t *valgen);
extern osc_t *new_osc_multiplex(osc_t *sel, osc_t *ox0, osc_t *ox1, osc_t *ox2, osc_t *ox3);
extern osc_t *new_osc_randphaser(int minphaselen, int maxphaselen);
extern osc_t *new_osc_constant(int val);
extern osc_t *new_osc_wrap(int min, int max, int step);
extern osc_t *new_osc_buffer(osc_t *val);
extern osc_t *new_osc_bounce(int min, int max, int step);
extern osc_t *new_osc_veryrandphaser(int minphaselen, int maxphaselen, int jitter);
extern void osc_free_all(void);
extern void osc_increment(void);
extern int osc_get(osc_t *osc, int elnum);
extern void set_transparency(float transparency);

// External functions from move.c and view.c
extern void win_draw(elem_t elist[]);
extern void win_reshape(int width, int height);
extern void setup_window(void);
extern void params_update(int wireframe, int edges, int shape);

// Global transparency variable
static float transparency = 1.0;

#define kName		@"stonerview"
#define kCurrentVersionsFile @"http://eblong.com/zarf/ftp/MacSoftwareVersions.plist"

// avb: Re-defined kVersion to an actual call to retrieve the version
#define kVersion (NSString*)CFBundleGetValueForInfoDictionaryKey (\
CFBundleGetBundleWithIdentifier(CFSTR("com.eblong.screensaver.stonerview")),CFSTR("CFBundleVersion"))

// #define LOG_DEBUG

@implementation StonerView

// Initialize instance-specific oscillators
- (void)initInstanceOscillators 
{
    // Base seeding value on this instance's display identifier
    int seed_offset = (int)(displaySeed % 100);
    
    // Create instance-specific oscillators with variations based on display seed
    theta = (void*)new_osc_linear(
        new_osc_velowrap(0, 36000, new_osc_multiplex(
          new_osc_randphaser(300 + seed_offset, 600 + seed_offset),
          new_osc_constant(25 + seed_offset % 10),
          new_osc_constant(75 + seed_offset % 15),
          new_osc_constant(50 + seed_offset % 12),
          new_osc_constant(100 + seed_offset % 20))
        ),
        new_osc_multiplex(
          new_osc_buffer(new_osc_randphaser(300 + seed_offset, 600 + seed_offset)),
          new_osc_buffer(new_osc_wrap(0, 36000, 10 + seed_offset % 5)),
          new_osc_buffer(new_osc_wrap(0, 36000, -8 - seed_offset % 4)),
          new_osc_wrap(0, 36000, 4 + seed_offset % 3),
          new_osc_buffer(new_osc_bounce(-2000, 2000, 20 + seed_offset % 8))
        )
    );
    
    rad = (void*)new_osc_buffer(new_osc_multiplex(
        new_osc_randphaser(250 + seed_offset, 500 + seed_offset),
        new_osc_bounce(-1000, 1000, 10 + seed_offset % 5),
        new_osc_bounce(  200, 1000, -15 - seed_offset % 7),
        new_osc_bounce(  400, 1000, 10 + seed_offset % 4),
        new_osc_bounce(-1000, 1000, -20 - seed_offset % 9)
    ));
    
    alti = (void*)new_osc_linear(
        new_osc_constant(-1000),
        new_osc_constant(2000 / NUM_ELS)
    );
    
    color = (void*)new_osc_multiplex(
        new_osc_buffer(new_osc_randphaser(150 + seed_offset, 300 + seed_offset)),
        new_osc_buffer(new_osc_wrap(0, 3600, 13 + seed_offset % 6)),
        new_osc_buffer(new_osc_wrap(0, 3600, 32 + seed_offset % 8)),
        new_osc_buffer(new_osc_wrap(0, 3600, 17 + seed_offset % 5)),
        new_osc_buffer(new_osc_wrap(0, 3600, 7 + seed_offset % 4))
    );
    
    shape_osc = (void*)new_osc_buffer(new_osc_veryrandphaser(500 + seed_offset, 1000 + seed_offset, 8 + seed_offset % 4));
}

// Cleanup instance oscillators
- (void)cleanupInstanceOscillators 
{
    // Nothing to do here - all oscilaltors are freed by osc_free_all
}

// Modified move_increment to work with instance-specific oscillators
- (void)move_increment_instance 
{
    int ix, val;
    GLfloat pt[2];
    GLfloat ptrad, pttheta;
    
    osc_t *theta_osc = (osc_t*)theta;
    osc_t *rad_osc = (osc_t*)rad;
    osc_t *alti_osc = (osc_t*)alti;
    osc_t *color_osc = (osc_t*)color;
    
    // Increment all our instance-specific oscillators
    osc_increment();
    
    for (ix=0; ix<NUM_ELS; ix++) {
        elem_t *el = &elist[ix];
        
        // Grab r and theta...
        val = osc_get(theta_osc, ix);
        pttheta = val * (0.01 * M_PI / 180.0); 
        ptrad = (GLfloat)osc_get(rad_osc, ix) * 0.001;
        
        // And convert them to x,y coordinates.
        pt[0] = ptrad * cos(pttheta);
        pt[1] = ptrad * sin(pttheta);
        
        // Set x,y,z.
        el->pos[0] = pt[0];
        el->pos[1] = pt[1];
        el->pos[2] = (GLfloat)osc_get(alti_osc, ix) * 0.001;
        
        // Set which way the square is rotated.
        el->vervec[0] = 0.11;
        el->vervec[1] = 0.0;
        
        // Set the color
        val = osc_get(color_osc, ix);
        
        // Convert HSV to RGB
        int ich = (val / 600);
        int icf = val % 600;
        if (ich >= 6)
            ich -= 6;
        
        switch (ich) {
            case 0:
                el->col[0] = 1.0;
                el->col[1] = ((GLfloat)icf) / 600.0;
                el->col[2] = 0.0;
                break;
            case 1:
                el->col[0] = 1.0 - ((GLfloat)icf) / 600.0;
                el->col[1] = 1.0;
                el->col[2] = 0.0;
                break;
            case 2:
                el->col[0] = 0.0;
                el->col[1] = 1.0;
                el->col[2] = ((GLfloat)icf) / 600.0;
                break;
            case 3:
                el->col[0] = 0.0;
                el->col[1] = 1.0 - ((GLfloat)icf) / 600.0;
                el->col[2] = 1.0;
                break;
            case 4:
                el->col[0] = ((GLfloat)icf) / 600.0;
                el->col[1] = 0.0;
                el->col[2] = 1.0;
                break;
            case 5:
                el->col[0] = 1.0;
                el->col[1] = 0.0;
                el->col[2] = 1.0 - ((GLfloat)icf) / 600.0;
                break;
        }
        
        // Set transparency (alpha)
        el->col[3] = transparency;
    }
}

// Instance-specific transparency setter
- (void)setInstanceTransparency:(float)newTransparency
{
    transparency = newTransparency;
}

- (id)initWithFrame:(NSRect)frameRect isPreview:(BOOL) preview
{
    NSString* version;

    ScreenSaverDefaults *defaults =
        [ScreenSaverDefaults defaultsForModuleWithName: kName];

    if (![super initWithFrame:frameRect isPreview:preview])
    {
        return nil;
    }
    
#ifdef LOG_DEBUG
    NSLog( @"initWithFrame" );
#endif

    if (self) {
        
        // Initialize unique seed for this display instance
        NSUInteger screenNumber = 0;
        if (@available(macOS 10.7, *)) {
            NSString *screenNumberString = [[[[self window] screen] deviceDescription] objectForKey:@"NSScreenNumber"];
            if (screenNumberString) {
                screenNumber = [screenNumberString unsignedIntegerValue];
            }
        }
        displaySeed = (screenNumber % 1000);
        
        NSOpenGLPixelFormatAttribute attribs[] = {
            NSOpenGLPFAAccelerated,
//		    NSOpenGLPFADepthSize, 16,
            NSOpenGLPFAColorSize, 16,
            NSOpenGLPFAMinimumPolicy,
            NSOpenGLPFAMaximumPolicy,
//		    NSOpenGLPFAClosestPolicy,
            0
        };
	
        NSOpenGLPixelFormat *format =
            [[[NSOpenGLPixelFormat alloc] initWithAttributes: attribs]
             autorelease];
		        
        _view = [[[NSOpenGLView alloc] initWithFrame: NSZeroRect
                                         pixelFormat: format]
                 autorelease];

        /* enable OpenGL hi-res display support
           https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/CapturingScreenContents/CapturingScreenContents.html#//apple_ref/doc/uid/TP40012302-CH10-SW35
         */

        [_view setWantsBestResolutionOpenGLSurface: YES];

        [self addSubview:_view];
    }
    
	// avb: There is a way to set factory defaults
	// This will have to be tweaked when a new version wants to
    // definitely change the users preferences

    /*
        if( ![version isEqualToString:kVersion] || (version == NULL) ) {
        // first time ever !!
     */

    NSDictionary *applicationDefaults =
        [NSDictionary dictionaryWithObjectsAndKeys:
            kVersion, @"version",
			kCFBooleanFalse, @"mainMonitorOnly",
			kCFBooleanFalse,@"wireframe",
			kCFBooleanFalse, @"edges",
			[NSNumber numberWithInt:0], @"shape",
			[NSNumber numberWithFloat:1.0], @"speed",
			[NSNumber numberWithFloat:0.75], @"alpha",
			nil];
	
	[defaults registerDefaults:applicationDefaults];
	[defaults synchronize];

	version   = [defaults stringForKey:@"version"];
    mainMonitorOnly = [defaults boolForKey:@"mainMonitorOnly"];
    wireframe = [defaults boolForKey:@"wireframe"];
    edges     = [defaults boolForKey:@"edges"];
    shape     = (int)[defaults integerForKey:@"shape"];
    speed     = [defaults floatForKey:@"speed"];
    alpha     = [defaults floatForKey:@"alpha"];
    
    return self;
}

- (void)animateOneFrame
{
#ifdef LOG_DEBUG
    // NSLog( @"animateOneFrame" );
#endif

    if( thisScreenIsOn == FALSE ) {
        [self stopAnimation];
        return;
    }

    NSOpenGLContext* context = [_view openGLContext];
    [context makeCurrentContext];
    
    // Enable vsync to prevent jitter
    [context setValues:(const GLint[]){1} forParameter:NSOpenGLCPSwapInterval];
    
    if (!_initedGL) {
        setup_window();

        /*  support for high resolution displays
            https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/CapturingScreenContents/CapturingScreenContents.html#//apple_ref/doc/uid/TP40012302-CH10-SW35
         */
        NSRect backingBounds =
            [_view convertRectToBacking:[_view bounds]];
        GLsizei backingPixelWidth  = (GLsizei)(backingBounds.size.width);
        GLsizei backingPixelHeight = (GLsizei)(backingBounds.size.height);
        
        win_reshape(backingPixelWidth, backingPixelHeight);
        
        // Use instance-specific oscillators instead of shared ones
        [self initInstanceOscillators];
        params_update(wireframe, edges, shape);
        [self move_increment_instance];
        [self move_increment_instance];
        [self move_increment_instance];
        [self setInstanceTransparency:alpha];
        
        _initedGL = YES;
    }

    [self move_increment_instance];  // Use instance-specific move_increment
    win_draw(elist);
    
    // Ensure the buffer swap is complete
    glFlush();
    
    return;
}

- (void)startAnimation
{
    NSOpenGLContext *context;
    int mainScreen;
    int thisScreen;

#ifdef LOG_DEBUG
    NSLog( @"startAnimation" );
#endif

    thisScreenIsOn = TRUE;
    if( mainMonitorOnly ) {
        thisScreen = [[[[[self window] screen] deviceDescription] objectForKey:@"NSScreenNumber"] intValue];
        mainScreen = [[[[NSScreen mainScreen] deviceDescription] objectForKey:@"NSScreenNumber"] intValue];
#ifdef LOG_DEBUG
        NSLog( @"Screen check: this %d - main %d", thisScreen, mainScreen );
#endif
        if( thisScreen != mainScreen ) {
            thisScreenIsOn = FALSE;
        }
    } else {
        // When not main monitor only, each instance should run independently
        thisScreenIsOn = TRUE;
    }

    // Do your animation initialization here
    
    context = [_view openGLContext];
    [context makeCurrentContext];
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glFlush();

    default_speed = [self animationTimeInterval];
    [self setAnimationTimeInterval:default_speed/speed];
    [super startAnimation];
}

- (void)stopAnimation
{
    // Do your animation termination here
#ifdef LOG_DEBUG
    NSLog( @"stopAnimation" );
#endif

    [super stopAnimation];
}

- (BOOL) hasConfigureSheet
{
    // Return YES if your screensaver has a ConfigureSheet
    return YES;
}

- (void) dealloc {

#ifdef LOG_DEBUG
    NSLog( @"dealloc" );
#endif
    [self cleanupInstanceOscillators];
    [_view removeFromSuperview];
    [super dealloc];
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [_view setFrameSize:newSize];
    _initedGL = NO;

}

- (NSWindow*)configureSheet
{
    NSBundle *thisBundle = [NSBundle bundleForClass:[self class]];

#ifdef LOG_DEBUG
    NSLog( @"configureSheet" );
#endif
    
    // Always reload the XIB to ensure clean state
    if (configureSheet) {
        configureSheet = nil;
    }
    
    BOOL success = [thisBundle loadNibNamed: @"StonerView"
                                  owner: self
                        topLevelObjects: nil];
    if (!success) {
        NSLog(@"Failed to load StonerView XIB");
    } else {
        // Ensure proper sheet behavior for modern macOS
        [configureSheet setLevel:NSModalPanelWindowLevel];
        if (@available(macOS 10.7, *)) {
            // Only set animationBehavior on newer versions
            // configureSheet.animationBehavior = NSWindowAnimationBehaviorDocumentWindow;
            // This property is only available on macOS 10.7+
        }
    }
    
    [IBversionNumberField setStringValue:kVersion];
    [IBUpdatesInfo setStringValue:@""];

    [IBview setTitle: [thisBundle localizedStringForKey: @"View"
                                                  value: @""
                                                  table: @""]];

    [IBwireframe setTitle: [thisBundle localizedStringForKey: @"Wireframe"
                                                       value: @""
                                                       table: @""]];
    [IBwireframe setState:(wireframe ? NSOnState : NSOffState)];

    [IBedges setTitle: [thisBundle localizedStringForKey: @"Edges"
                                                   value: @""
                                                   table: @""]];
    [IBedges setState:(edges ? NSOnState : NSOffState)];

    [IBshapeTxt setStringValue:
        [thisBundle localizedStringForKey:@"Shape" value:@"" table:@""]];
    [IBshape addItemWithTitle:
        [thisBundle localizedStringForKey:@"Random" value:@"" table:@""]];
    [IBshape addItemWithTitle:
        [thisBundle localizedStringForKey:@"Quads" value:@"" table:@""]];
    [IBshape addItemWithTitle:
        [thisBundle localizedStringForKey:@"Triangles" value:@"" table:@""]];
    [IBshape addItemWithTitle:
        [thisBundle localizedStringForKey:@"Hexagons" value:@"" table:@""]];
    [IBshape addItemWithTitle:
        [thisBundle localizedStringForKey:@"Discs" value:@"" table:@""]];
    [IBshape addItemWithTitle:
        [thisBundle localizedStringForKey:@"Spheres" value:@"" table:@""]];
    [IBshape addItemWithTitle:
        [thisBundle localizedStringForKey:@"Cubes" value:@"" table:@""]];
    [IBshape addItemWithTitle:
        [thisBundle localizedStringForKey:@"Cones" value:@"" table:@""]];
    [IBshape addItemWithTitle:
        [thisBundle localizedStringForKey:@"Toruses" value:@"" table:@""]];
    [IBshape selectItemAtIndex:shape];

    [IBspeedTxt setStringValue:
        [thisBundle localizedStringForKey:@"Speed" value:@"" table:@""]];
    [IBspeed setFloatValue:speed];
    [IBslow setStringValue:
        [thisBundle localizedStringForKey:@"slow" value:@"" table:@""]];
    [IBfast setStringValue:
        [thisBundle localizedStringForKey:@"fast" value:@"" table:@""]];

    [IBalphaTxt setStringValue:
        [thisBundle localizedStringForKey:@"Transp." value:@"" table:@""]];
    [IBalpha setFloatValue:alpha*10];

    [IBmainMonitorOnly setState:(mainMonitorOnly ? NSOnState : NSOffState)];

    [IBmainMonitorOnly setTitle:
        [thisBundle localizedStringForKey: @"Main monitor only"
                                    value: @""
                                    table: @""]];

    [IBCheckVersion setTitle:
        [thisBundle localizedStringForKey: @"Check updates"
                                    value: @""
                                    table: @""]];

    [IBCancel setTitle:
        [thisBundle localizedStringForKey: @"Cancel"
                                    value: @""
                                    table: @""]];
    
    [IBSave setTitle: [thisBundle localizedStringForKey: @"Save"
                                                  value: @""
                                                  table: @""]];

    return configureSheet;
}

- (IBAction) closeSheet_save:(id) sender {

    int thisScreen;
    int mainScreen;

    ScreenSaverDefaults *defaults =
        [ScreenSaverDefaults defaultsForModuleWithName:kName];
    
#ifdef LOG_DEBUG
    NSLog( @"closeSheet_save" );
#endif

    mainMonitorOnly =
        ( [IBmainMonitorOnly state] == NSOnState ) ? true : false;

    wireframe	 = ( [IBwireframe state] == NSOnState ) ? true : false;
    edges	 = ( [IBedges state] == NSOnState ) ? true : false;
    shape        = (int)[IBshape indexOfSelectedItem];
    speed        = [IBspeed floatValue];
    alpha        = [IBalpha floatValue]/10.0;

    [defaults setBool: mainMonitorOnly forKey: @"mainMonitorOnly"];
    [defaults setBool:wireframe forKey:@"wireframe"];
    [defaults setBool:edges forKey:@"edges"];
    [defaults setInteger:shape forKey:@"shape"];
    [defaults setFloat:speed forKey:@"speed"];
    [defaults setFloat:alpha forKey:@"alpha"];
    [defaults synchronize];

#ifdef LOG_DEBUG
    NSLog(@"Canged params" );
#endif

    if( mainMonitorOnly ) {
        thisScreen = [[[[[self window] screen] deviceDescription] objectForKey:@"NSScreenNumber"] intValue];
        mainScreen = [[[[NSScreen mainScreen] deviceDescription] objectForKey:@"NSScreenNumber"] intValue];
        // NSLog( @"test this %d - main %d", thisScreen, mainScreen );
        if( thisScreen != mainScreen ) {
            thisScreenIsOn = FALSE;
        }
    }
    if( (thisScreenIsOn == FALSE) && (mainMonitorOnly == FALSE) ) {
        thisScreenIsOn = TRUE;
        [self startAnimation];
    }
    
    params_update(wireframe, edges, shape);
    [self setInstanceTransparency:alpha];
    [self setAnimationTimeInterval:default_speed/speed];

    // Properly close the sheet for modern macOS
    [[self window] endSheet:configureSheet];
    [configureSheet orderOut:sender];
    
    // Clear the reference to allow for fresh loading next time
    configureSheet = nil;
}

- (IBAction) closeSheet_cancel:(id) sender {

#ifdef LOG_DEBUG
    NSLog( @"closeSheet_cancel" );
#endif
    
    params_update(wireframe, edges, shape);
    [self setInstanceTransparency:alpha];
    [self setAnimationTimeInterval:default_speed/speed];

    // Properly close the sheet for modern macOS
    [[self window] endSheet:configureSheet];
    [configureSheet orderOut:sender];
    
    // Clear the reference to allow for fresh loading next time
    configureSheet = nil;
}

- (IBAction)updateConfigureSheet:(id) sender
{
    BOOL wireframe_test, edges_test;
    int shape_test;
    float speed_test;
    float alpha_test;
    
#ifdef LOG_DEBUG
    NSLog( @"updateConfigureSheet" );
#endif
    
    wireframe_test = ( [IBwireframe state] == NSOnState ) ? true : false;
    edges_test	   = ( [IBedges state] == NSOnState ) ? true : false;
    shape_test     = (int)[IBshape indexOfSelectedItem];
    speed_test     = [IBspeed floatValue];
    alpha_test     = [IBalpha floatValue]/10.0;
    
    params_update(wireframe_test, edges_test, shape_test);
    [self setInstanceTransparency:alpha_test];    
    [self setAnimationTimeInterval:default_speed/speed_test];
}

- (IBAction) checkUpdates:(id)sender
{
    NSString *testVersionString;
    NSDictionary *theVersionDict;
    NSString *theVersion;
    NSBundle *thisBundle = [NSBundle bundleForClass:[self class]];

    testVersionString =
        [NSString stringWithContentsOfURL:
            [NSURL URLWithString: kCurrentVersionsFile]
                        encoding: kCFStringEncodingUTF8
                           error: nil];

    if( testVersionString == nil ) {
        // no connection with the server
        [IBUpdatesInfo setStringValue:
            [thisBundle localizedStringForKey:
                @"Couldn't download version information."
                                        value: @""
                                        table: @""]];
    }
    else {
        theVersionDict = [testVersionString propertyList];
        theVersion = [theVersionDict objectForKey:kName];

        if ( ![theVersion isEqualToString:kVersion] ) {
            // hopefully our version numbers will never be going down...
            // also takes care of going from MyGreatApp? 7.5 to
            // SuperMyGreatApp? Pro 1.0
            [IBUpdatesInfo setStringValue:
                [thisBundle localizedStringForKey: @"New version available!"
                                            value: @""
                                            table: @""]];
        }
        else {
            [IBUpdatesInfo setStringValue:
                [thisBundle localizedStringForKey: @"You're up-to-date!"
                                            value: @""
                                            table: @""]];
        }
    }
}

@end
