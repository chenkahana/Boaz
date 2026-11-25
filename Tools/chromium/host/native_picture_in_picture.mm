#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include "native_picture_in_picture.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <string>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "base/values.h"
#include "bootstrap.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/video_picture_in_picture_window_controller.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "ui/gfx/native_ui_types.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_observer.h"

typedef NS_ENUM(NSInteger, BoazPiPAction) {
  BoazPiPActionTogglePlay,
  BoazPiPActionSeekTo,
  BoazPiPActionSeekBy,
  BoazPiPActionSeekFraction,
  BoazPiPActionSetVolume,
  BoazPiPActionToggleMute,
  BoazPiPActionSetRate,
  BoazPiPActionBackToTab,
  BoazPiPActionClose,
};
typedef void (^BoazPiPHandler)(BoazPiPAction action, double value);

namespace {
constexpr std::array<double, 8> kRates = {0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2};
NSString* TimeText(double seconds) {
  const long total = std::isfinite(seconds) ? std::max(0L, std::lround(std::floor(seconds))) : 0;
  const long hours = total / 3600, minutes = total / 60 % 60, rest = total % 60;
  return hours ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", hours, minutes, rest]
               : [NSString stringWithFormat:@"%ld:%02ld", minutes, rest];
}
NSString* RateText(double rate) {
  return [NSString stringWithFormat:@"%@×", [NSNumberFormatter localizedStringFromNumber:@(rate)
                                                                            numberStyle:NSNumberFormatterDecimalStyle]];
}
NSShadow* ControlShadow() {
  NSShadow* shadow = [[NSShadow alloc] init];
  shadow.shadowBlurRadius = 4;
  shadow.shadowOffset = NSMakeSize(0, -1);
  shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.45];
  return shadow;
}
}  // namespace

// Lays out its controls from the top left, as the controls view does.
@interface BoazPiPFlippedView : NSView
@end
@implementation BoazPiPFlippedView
- (BOOL)isFlipped { return YES; }
@end

// A white, borderless control that lights a round plate under the pointer.
@interface BoazPiPButton : NSButton
@end
@implementation BoazPiPButton {
  CGFloat _pointSize;
  NSTrackingArea* _area;
}
- (instancetype)initWithPointSize:(CGFloat)pointSize target:(id)target action:(SEL)action {
  if ((self = [super initWithFrame:NSZeroRect])) {
    _pointSize = pointSize;
    self.bordered = NO;
    self.imagePosition = NSImageOnly;
    self.imageScaling = NSImageScaleNone;
    self.contentTintColor = NSColor.whiteColor;
    self.focusRingType = NSFocusRingTypeNone;
    self.refusesFirstResponder = YES;
    self.wantsLayer = YES;
    self.shadow = ControlShadow();
    self.target = target;
    self.action = action;
  }
  return self;
}
- (void)setSymbol:(NSString*)symbol label:(NSString*)label {
  NSImage* image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
  self.image = [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration
                                                       configurationWithPointSize:_pointSize
                                                                           weight:NSFontWeightSemibold]];
  self.toolTip = label;
  self.accessibilityLabel = label;
}
- (void)setText:(NSString*)text label:(NSString*)label {
  self.imagePosition = NSNoImage;
  self.attributedTitle = [[NSAttributedString alloc]
      initWithString:text
          attributes:@{NSForegroundColorAttributeName : NSColor.whiteColor,
                       NSFontAttributeName : [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightSemibold]}];
  self.toolTip = label;
  self.accessibilityLabel = label;
}
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)layout {
  [super layout];
  self.layer.cornerRadius = std::min(NSWidth(self.bounds), NSHeight(self.bounds)) / 2;
}
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_area) [self removeTrackingArea:_area];
  _area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                       options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways |
                                               NSTrackingInVisibleRect
                                         owner:self
                                      userInfo:nil];
  [self addTrackingArea:_area];
}
- (void)mouseEntered:(NSEvent*)event { self.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.16].CGColor; }
- (void)mouseExited:(NSEvent*)event { self.layer.backgroundColor = nil; }
- (void)viewDidHide { self.layer.backgroundColor = nil; }
@end

// A YouTube-style bar: a thin track that thickens under the pointer, the buffered range, the played part and a knob.
@interface BoazPiPBar : NSView
@property(nonatomic) double value;
@property(nonatomic) double buffered;
@property(nonatomic, strong) NSColor* fillColor;
@property(nonatomic, readonly) BOOL tracking;
@property(nonatomic, readonly) BOOL hovered;
@property(nonatomic, copy) void (^onChange)(double value, BOOL finished);
@property(nonatomic, copy) void (^onHover)(double value, BOOL inside);
@end
@implementation BoazPiPBar {
  NSTrackingArea* _area;
}
@synthesize value = _value;
@synthesize buffered = _buffered;
@synthesize fillColor = _fillColor;
@synthesize tracking = _tracking;
@synthesize hovered = _hovered;
@synthesize onChange = _onChange;
@synthesize onHover = _onHover;
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)setValue:(double)value {
  _value = std::clamp(std::isfinite(value) ? value : 0, 0.0, 1.0);
  self.needsDisplay = YES;
}
- (void)setBuffered:(double)buffered {
  _buffered = std::clamp(std::isfinite(buffered) ? buffered : 0, 0.0, 1.0);
  self.needsDisplay = YES;
}
- (CGFloat)inset { return 6; }
- (double)valueAt:(NSEvent*)event {
  const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  const CGFloat width = std::max<CGFloat>(1, NSWidth(self.bounds) - 2 * self.inset);
  return std::clamp((point.x - self.inset) / width, 0.0, 1.0);
}
- (void)drawRect:(NSRect)dirty {
  const BOOL active = _hovered || _tracking;
  const CGFloat height = active ? 5 : 3, width = NSWidth(self.bounds) - 2 * self.inset;
  const NSRect track = NSMakeRect(self.inset, (NSHeight(self.bounds) - height) / 2, width, height);
  auto fill = [&](double fraction, NSColor* color) {
    if (fraction <= 0) return;
    NSRect part = track;
    part.size.width = width * fraction;
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:part xRadius:height / 2 yRadius:height / 2] fill];
  };
  fill(1, [NSColor colorWithWhite:1 alpha:0.3]);
  fill(_buffered, [NSColor colorWithWhite:1 alpha:0.55]);
  fill(_value, _fillColor ?: NSColor.whiteColor);
  if (!active) return;
  const CGFloat knob = 12, x = self.inset + width * _value;
  [(_fillColor ?: NSColor.whiteColor) setFill];
  [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - knob / 2, (NSHeight(self.bounds) - knob) / 2, knob, knob)]
      fill];
}
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_area) [self removeTrackingArea:_area];
  _area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                       options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                                               NSTrackingActiveAlways | NSTrackingInVisibleRect
                                         owner:self
                                      userInfo:nil];
  [self addTrackingArea:_area];
}
- (void)mouseEntered:(NSEvent*)event {
  _hovered = YES;
  self.needsDisplay = YES;
  if (_onHover) _onHover([self valueAt:event], YES);
}
- (void)mouseMoved:(NSEvent*)event {
  if (_onHover) _onHover([self valueAt:event], YES);
}
- (void)mouseExited:(NSEvent*)event {
  _hovered = NO;
  self.needsDisplay = YES;
  if (_onHover && !_tracking) _onHover(0, NO);
}
- (void)mouseDown:(NSEvent*)event {
  _tracking = YES;
  [self mouseDragged:event];
}
- (void)mouseDragged:(NSEvent*)event {
  self.value = [self valueAt:event];
  if (_onHover) _onHover(_value, YES);
  if (_onChange) _onChange(_value, NO);
}
- (void)mouseUp:(NSEvent*)event {
  self.value = [self valueAt:event];
  _tracking = NO;
  self.needsDisplay = YES;
  if (_onChange) _onChange(_value, YES);
  if (_onHover) _onHover(_value, _hovered);
}
- (void)viewDidHide {
  _hovered = NO;
  self.needsDisplay = YES;
}
@end

// Boaz's controls over Chromium's video: they appear while the pointer is over the window and fade after a moment of
// stillness, as in YouTube's player, and stay while the video is paused.
@interface BoazPiPControlsView : NSView
@property(nonatomic, copy) BoazPiPHandler handler;
@property(nonatomic) BOOL suppressed;
- (void)setMediaAvailable:(BOOL)available playing:(BOOL)playing;
- (void)setPaused:(BOOL)paused
          current:(double)current
         duration:(double)duration
         buffered:(double)buffered
           volume:(double)volume
            muted:(BOOL)muted
             rate:(double)rate;
- (BOOL)handleKey:(NSEvent*)event;
- (void)stop;
@end

@implementation BoazPiPControlsView {
  NSView* _chrome;
  CAGradientLayer* _topScrim;
  CAGradientLayer* _bottomScrim;
  BoazPiPButton* _back;
  BoazPiPButton* _close;
  BoazPiPButton* _play;
  BoazPiPButton* _replay;
  BoazPiPButton* _forward;
  BoazPiPButton* _mute;
  BoazPiPBar* _volumeBar;
  NSTextField* _time;
  BoazPiPButton* _rateButton;
  BoazPiPBar* _seek;
  NSTextField* _seekBubble;
  NSView* _flash;
  NSImageView* _flashImage;
  NSTextField* _flashText;
  NSTrackingArea* _area;
  id _moveObserver;
  BOOL _available, _paused, _muted, _inside, _active, _overControls, _volumeOpen, _menuOpen, _shown, _dragging;
  double _current, _duration, _volume, _rate;
  CFTimeInterval _lastSeek, _lastToggle, _lastScrubSend;
}
@synthesize handler = _handler;
@synthesize suppressed = _suppressed;

- (instancetype)initWithFrame:(NSRect)frame {
  if (!(self = [super initWithFrame:frame])) return nil;
  self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  _paused = NO;
  _volume = 1;
  _rate = 1;
  _chrome = [[BoazPiPFlippedView alloc] initWithFrame:self.bounds];
  _chrome.wantsLayer = YES;
  _chrome.alphaValue = 0;
  _chrome.hidden = YES;
  _topScrim = [CAGradientLayer layer];
  _topScrim.colors = @[ (id)[NSColor colorWithWhite:0 alpha:0.55].CGColor, (id)NSColor.clearColor.CGColor ];
  _bottomScrim = [CAGradientLayer layer];
  _bottomScrim.colors = @[ (id)NSColor.clearColor.CGColor, (id)[NSColor colorWithWhite:0 alpha:0.7].CGColor ];
  for (CAGradientLayer* scrim in @[ _topScrim, _bottomScrim ]) {
    scrim.actions = @{@"bounds" : NSNull.null, @"position" : NSNull.null};
    [_chrome.layer addSublayer:scrim];
  }
  [self addSubview:_chrome];

  _back = [self button:17 action:@selector(backToTab:)];
  [_back setSymbol:@"arrow.up.left.and.arrow.down.right" label:@"Back to tab (f)"];
  _close = [self button:16 action:@selector(close:)];
  [_close setSymbol:@"xmark" label:@"Close"];
  _replay = [self button:22 action:@selector(replay:)];
  [_replay setSymbol:@"gobackward.10" label:@"Back 10 seconds (j)"];
  _play = [self button:30 action:@selector(togglePlay:)];
  _forward = [self button:22 action:@selector(forward:)];
  [_forward setSymbol:@"goforward.10" label:@"Forward 10 seconds (l)"];
  _mute = [self button:15 action:@selector(toggleMute:)];
  _rateButton = [self button:12 action:@selector(showRates:)];

  __weak BoazPiPControlsView* weakSelf = self;
  _volumeBar = [[BoazPiPBar alloc] initWithFrame:NSZeroRect];
  _volumeBar.onChange = ^(double value, BOOL finished) {
    [weakSelf send:BoazPiPActionSetVolume value:value];
  };
  _volumeBar.accessibilityLabel = @"Volume";
  [_chrome addSubview:_volumeBar];

  _seek = [[BoazPiPBar alloc] initWithFrame:NSZeroRect];
  _seek.fillColor = NSColor.controlAccentColor;
  _seek.accessibilityLabel = @"Seek";
  _seek.onChange = ^(double value, BOOL finished) { [weakSelf scrubTo:value finished:finished]; };
  _seek.onHover = ^(double value, BOOL inside) { [weakSelf showBubbleAt:value visible:inside]; };
  [_chrome addSubview:_seek];

  _time = [self label:[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium]];
  [_chrome addSubview:_time];
  _seekBubble = [self label:[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightSemibold]];
  _seekBubble.alignment = NSTextAlignmentCenter;
  _seekBubble.wantsLayer = YES;
  _seekBubble.drawsBackground = YES;
  _seekBubble.backgroundColor = [NSColor colorWithWhite:0.1 alpha:0.85];
  _seekBubble.layer.cornerRadius = 4;
  _seekBubble.shadow = nil;
  _seekBubble.hidden = YES;
  [_chrome addSubview:_seekBubble];

  _flash = [[NSView alloc] initWithFrame:NSZeroRect];
  _flash.wantsLayer = YES;
  _flash.layer.backgroundColor = [NSColor colorWithWhite:0 alpha:0.55].CGColor;
  _flash.alphaValue = 0;
  _flashImage = [[NSImageView alloc] initWithFrame:NSZeroRect];
  _flashImage.contentTintColor = NSColor.whiteColor;
  _flashText = [self label:[NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold]];
  _flashText.alignment = NSTextAlignmentCenter;
  _flashText.shadow = nil;
  [_flash addSubview:_flashImage];
  [_flash addSubview:_flashText];
  [self addSubview:_flash];

  [self setMediaAvailable:NO playing:YES];
  [self updateVolume];
  [self updateRate];
  return self;
}

- (BoazPiPButton*)button:(CGFloat)pointSize action:(SEL)action {
  BoazPiPButton* button = [[BoazPiPButton alloc] initWithPointSize:pointSize target:self action:action];
  [_chrome addSubview:button];
  return button;
}

- (NSTextField*)label:(NSFont*)font {
  NSTextField* label = [NSTextField labelWithString:@""];
  label.font = font;
  label.textColor = NSColor.whiteColor;
  label.shadow = ControlShadow();
  label.lineBreakMode = NSLineBreakByClipping;
  return label;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }

- (void)stop {
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  if (_moveObserver) [NSNotificationCenter.defaultCenter removeObserver:_moveObserver];
  _moveObserver = nil;
  _handler = nil;
}

- (void)send:(BoazPiPAction)action value:(double)value {
  if (_handler) _handler(action, value);
}

#pragma mark Layout

- (void)layout {
  [super layout];
  const NSRect bounds = self.bounds;
  const CGFloat w = NSWidth(bounds), h = NSHeight(bounds);
  _chrome.frame = bounds;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  const CGFloat top = std::min<CGFloat>(64, h * 0.4), bottom = std::min<CGFloat>(104, h * 0.6);
  _topScrim.frame = NSMakeRect(0, 0, w, top);
  _bottomScrim.frame = NSMakeRect(0, h - bottom, w, bottom);
  [CATransaction commit];

  _back.frame = NSMakeRect(8, 8, 30, 30);
  _close.frame = NSMakeRect(w - 38, 8, 30, 30);

  const CGFloat play = h < 170 ? 44 : 56, skip = h < 170 ? 36 : 44, gap = w < 300 ? 52 : 72;
  _play.frame = NSMakeRect(std::round((w - play) / 2), std::round((h - play) / 2), play, play);
  _replay.frame = NSMakeRect(std::round(w / 2 - gap - skip / 2), std::round((h - skip) / 2), skip, skip);
  _forward.frame = NSMakeRect(std::round(w / 2 + gap - skip / 2), std::round((h - skip) / 2), skip, skip);
  const BOOL roomy = w >= 230 && h >= 120;
  _replay.hidden = _forward.hidden = !_available || !roomy;

  const CGFloat row = h - 36;
  _mute.frame = NSMakeRect(8, row, 28, 28);
  const CGFloat volume = _volumeOpen && w >= 260 ? 64 : 0;
  _volumeBar.frame = NSMakeRect(36, row + 4, volume, 20);
  _volumeBar.hidden = volume == 0;
  _rateButton.frame = NSMakeRect(w - 8 - 44, row, 44, 28);
  _rateButton.hidden = !_available || w < 200;
  const CGFloat timeX = 36 + volume + 4;
  _time.frame = NSMakeRect(timeX, row + 6, std::max<CGFloat>(0, NSMinX(_rateButton.frame) - timeX - 4), 16);
  _seek.frame = NSMakeRect(6, row - 18, w - 12, 18);
  _seek.hidden = !_available || _duration <= 0;
  _mute.hidden = !_available;
  _time.hidden = !_available;

  _flash.frame = NSMakeRect(std::round((w - 76) / 2), std::round((h - 76) / 2), 76, 76);
  _flash.layer.cornerRadius = 38;
  _flashImage.frame = NSMakeRect(18, 14, 40, 34);
  _flashText.frame = NSMakeRect(0, 48, 76, 18);
}

#pragma mark State

- (void)setMediaAvailable:(BOOL)available playing:(BOOL)playing {
  _available = available;
  if (!available) {
    _paused = !playing;
    [self updatePlay];
  }
  self.needsLayout = YES;
}

- (void)setPaused:(BOOL)paused
          current:(double)current
         duration:(double)duration
         buffered:(double)buffered
           volume:(double)volume
            muted:(BOOL)muted
             rate:(double)rate {
  const BOOL wasAvailable = _available, hadDuration = _duration > 0;
  _available = YES;
  // A reply already on its way when the user pressed play or pause still carries the old state.
  if (CACurrentMediaTime() - _lastToggle > 0.5) _paused = paused;
  _duration = duration;
  _volume = volume;
  _muted = muted;
  _rate = rate;
  // Ignore stale positions for a moment after a seek so the knob doesn't jump back.
  if (!_seek.tracking && CACurrentMediaTime() - _lastSeek > 0.6) _current = current;
  if (duration > 0) {
    if (!_seek.tracking) _seek.value = _current / duration;
    _seek.buffered = buffered / duration;
  }
  if (!_volumeBar.tracking) _volumeBar.value = muted ? 0 : volume;
  [self updatePlay];
  [self updateTime];
  [self updateVolume];
  [self updateRate];
  if (!wasAvailable || hadDuration != (duration > 0)) self.needsLayout = YES;
  [self updateChromeVisibility];
}

- (void)updatePlay {
  [_play setSymbol:_paused ? @"play.fill" : @"pause.fill" label:_paused ? @"Play (k)" : @"Pause (k)"];
}

- (void)updateTime {
  if (_duration < 0) {
    NSMutableAttributedString* live = [[NSMutableAttributedString alloc]
        initWithString:@"● "
            attributes:@{NSForegroundColorAttributeName : NSColor.systemRedColor, NSFontAttributeName : _time.font}];
    [live appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:@"LIVE"
                                         attributes:@{NSForegroundColorAttributeName : NSColor.whiteColor,
                                                      NSFontAttributeName : _time.font}]];
    _time.attributedStringValue = live;
    return;
  }
  NSString* current = TimeText(_current);
  _time.stringValue = _duration > 0 && NSWidth(self.bounds) >= 240
                          ? [NSString stringWithFormat:@"%@ / %@", current, TimeText(_duration)]
                          : current;
}

- (void)updateVolume {
  NSString* symbol = _muted || _volume == 0 ? @"speaker.slash.fill"
                     : _volume < 0.34       ? @"speaker.wave.1.fill"
                     : _volume < 0.67       ? @"speaker.wave.2.fill"
                                            : @"speaker.wave.3.fill";
  [_mute setSymbol:symbol label:_muted ? @"Unmute (m)" : @"Mute (m)"];
}

- (void)updateRate {
  [_rateButton setText:RateText(_rate) label:@"Playback speed"];
}

#pragma mark Visibility

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_area) [self removeTrackingArea:_area];
  _area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                       options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                                               NSTrackingActiveAlways | NSTrackingInVisibleRect
                                         owner:self
                                      userInfo:nil];
  [self addTrackingArea:_area];
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (_moveObserver) [NSNotificationCenter.defaultCenter removeObserver:_moveObserver];
  _moveObserver = nil;
  if (!self.window) return;
  __weak BoazPiPControlsView* weakSelf = self;
  _moveObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidMoveNotification
                                                                  object:self.window
                                                                   queue:nil
                                                              usingBlock:^(NSNotification*) {
                                                                [weakSelf windowMoved];
                                                              }];
}

- (void)pointerMoved:(NSEvent*)event {
  _inside = YES;
  _active = YES;
  const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  NSView* hit = [super hitTest:[self convertPoint:point toView:self.superview]];
  _overControls = hit && hit != self && hit != _chrome;
  const NSRect volumeZone = NSInsetRect(NSUnionRect(_mute.frame, NSOffsetRect(_mute.frame, 72, 0)), -4, -6);
  const BOOL volumeOpen = _available && (NSPointInRect(point, volumeZone) || _volumeBar.tracking);
  if (volumeOpen != _volumeOpen) {
    _volumeOpen = volumeOpen;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
      context.duration = 0.15;
      context.allowsImplicitAnimation = YES;
      self.needsLayout = YES;
      [self layoutSubtreeIfNeeded];
    }];
    [self updateTime];
  }
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(becameIdle) object:nil];
  [self performSelector:@selector(becameIdle) withObject:nil afterDelay:2.5];
  [self updateChromeVisibility];
}

- (void)mouseEntered:(NSEvent*)event { [self pointerMoved:event]; }
- (void)mouseMoved:(NSEvent*)event { [self pointerMoved:event]; }
- (void)mouseExited:(NSEvent*)event {
  _inside = NO;
  _overControls = NO;
  if (_volumeOpen && !_volumeBar.tracking) {
    _volumeOpen = NO;
    self.needsLayout = YES;
  }
  [self updateChromeVisibility];
}

- (void)becameIdle {
  _active = NO;
  [self updateChromeVisibility];
}

- (void)updateChromeVisibility {
  // The window can move or resize away from a still pointer without an exit event.
  if (_inside && !NSPointInRect(NSEvent.mouseLocation, self.window.frame)) {
    _inside = NO;
    _overControls = NO;
  }
  const BOOL busy = _seek.tracking || _volumeBar.tracking || _menuOpen || _dragging;
  const BOOL show = !_suppressed && (busy || (_inside && (_active || _paused || _overControls)));
  if (show == _shown) return;
  _shown = show;
  if (show) _chrome.hidden = NO;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
    context.duration = show ? 0.12 : 0.25;
    self->_chrome.animator.alphaValue = show ? 1 : 0;
  }
      completionHandler:^{
        if (!self->_shown) self->_chrome.hidden = YES;
      }];
  if (!show) _seekBubble.hidden = YES;
}

- (void)setSuppressed:(BOOL)suppressed {
  if (_suppressed == suppressed) return;
  _suppressed = suppressed;
  [self updateChromeVisibility];
}

// Edges stay with the window so it can be resized; the rest of the video is Boaz's.
- (NSView*)hitTest:(NSPoint)point {
  if (_suppressed) return nil;
  const NSPoint local = [self convertPoint:point fromView:self.superview];
  if (!NSPointInRect(local, NSInsetRect(self.bounds, 5, 5))) return nil;
  NSView* hit = [super hitTest:point];
  return hit == _chrome || hit == _flash || [hit isDescendantOf:_flash] ? self : hit;
}

#pragma mark Pointer on the video

// A click plays or pauses, as in YouTube; a drag moves the window and snaps it to the screen's edges and corners.
- (void)mouseDown:(NSEvent*)event {
  NSEvent* next = [self.window nextEventMatchingMask:NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged
                                           untilDate:NSDate.distantFuture
                                              inMode:NSEventTrackingRunLoopMode
                                             dequeue:YES];
  if (next.type == NSEventTypeLeftMouseDragged) {
    _dragging = YES;
    [self.window performWindowDragWithEvent:event];
    [self finishDragWhenReleased];
    return;
  }
  [self togglePlay:nil];
}

- (void)finishDragWhenReleased {
  if (NSEvent.pressedMouseButtons & 1) {
    [self performSelector:@selector(finishDragWhenReleased) withObject:nil afterDelay:0.05];
    return;
  }
  _dragging = NO;
  [self snapToScreen];
  [self updateChromeVisibility];
}

- (void)windowMoved {
  if (_dragging) return;
  // A window that lands off a display (one was unplugged, say) comes back onto the nearest one.
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(keepOnScreen) object:nil];
  [self performSelector:@selector(keepOnScreen) withObject:nil afterDelay:0.3];
}

- (void)keepOnScreen {
  NSWindow* window = self.window;
  if (!window || NSEvent.pressedMouseButtons & 1) return;
  for (NSScreen* screen in NSScreen.screens) {
    if (NSContainsRect(screen.visibleFrame, window.frame)) return;
  }
  [self snapToScreen];
}

- (void)snapToScreen {
  NSWindow* window = self.window;
  NSScreen* screen = window.screen ?: NSScreen.mainScreen;
  if (!window || !screen) return;
  constexpr CGFloat kMargin = 12, kReach = 48;
  const NSRect area = NSInsetRect(screen.visibleFrame, kMargin, kMargin);
  NSRect frame = window.frame;
  auto snap = [&](CGFloat origin, CGFloat size, CGFloat low, CGFloat high) {
    if (size >= high - low) return low;
    if (origin - low < kReach) return low;
    if (high - (origin + size) < kReach) return high - size;
    return origin;
  };
  frame.origin.x = snap(NSMinX(frame), NSWidth(frame), NSMinX(area), NSMaxX(area));
  frame.origin.y = snap(NSMinY(frame), NSHeight(frame), NSMinY(area), NSMaxY(area));
  if (NSEqualRects(frame, window.frame)) return;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
    context.duration = 0.18;
    context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [window.animator setFrame:frame display:YES];
  }];
}

#pragma mark Actions

- (void)togglePlay:(id)sender {
  _lastToggle = CACurrentMediaTime();
  _paused = !_paused;
  [self updatePlay];
  [self send:BoazPiPActionTogglePlay value:0];
  if (!sender) [self flashSymbol:_paused ? @"pause.fill" : @"play.fill" text:nil];
  [self updateChromeVisibility];
}
- (void)replay:(id)sender { [self seekBy:-10]; }
- (void)forward:(id)sender { [self seekBy:10]; }
- (void)seekBy:(double)seconds {
  _lastSeek = CACurrentMediaTime();
  _current = std::max(0.0, _duration > 0 ? std::min(_duration, _current + seconds) : _current + seconds);
  if (_duration > 0) _seek.value = _current / _duration;
  [self updateTime];
  [self send:BoazPiPActionSeekBy value:seconds];
}
- (void)toggleMute:(id)sender {
  _muted = !_muted;
  if (!_muted && _volume == 0) _volume = 0.5;
  _volumeBar.value = _muted ? 0 : _volume;
  [self updateVolume];
  [self send:BoazPiPActionToggleMute value:0];
}
- (void)backToTab:(id)sender { [self send:BoazPiPActionBackToTab value:0]; }
- (void)close:(id)sender { [self send:BoazPiPActionClose value:0]; }

- (void)showRates:(id)sender {
  NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Playback speed"];
  NSMenuItem* current = nil;
  for (double rate : kRates) {
    NSMenuItem* item = [menu addItemWithTitle:rate == 1 ? @"Normal" : RateText(rate)
                                       action:@selector(chooseRate:)
                                keyEquivalent:@""];
    item.target = self;
    item.representedObject = @(rate);
    if (std::abs(rate - _rate) < 0.001) {
      item.state = NSControlStateValueOn;
      current = item;
    }
  }
  _menuOpen = YES;
  [menu popUpMenuPositioningItem:current atLocation:NSMakePoint(0, 0) inView:_rateButton];
  _menuOpen = NO;
  [self updateChromeVisibility];
}
- (void)chooseRate:(NSMenuItem*)item { [self setRate:[item.representedObject doubleValue]]; }
- (void)setRate:(double)rate {
  _rate = rate;
  [self updateRate];
  [self send:BoazPiPActionSetRate value:rate];
}

- (void)scrubTo:(double)value finished:(BOOL)finished {
  if (_duration <= 0) return;
  _current = value * _duration;
  _lastSeek = CACurrentMediaTime();
  [self updateTime];
  const CFTimeInterval now = CACurrentMediaTime();
  if (finished || now - _lastScrubSend > 0.12) {
    _lastScrubSend = now;
    [self send:BoazPiPActionSeekTo value:_current];
  }
  [self updateChromeVisibility];
}

- (void)showBubbleAt:(double)value visible:(BOOL)visible {
  _seekBubble.hidden = !visible || _duration <= 0;
  if (_seekBubble.hidden) return;
  _seekBubble.stringValue = TimeText(value * _duration);
  const CGFloat width = [_seekBubble.stringValue sizeWithAttributes:@{NSFontAttributeName : _seekBubble.font}].width + 12;
  const CGFloat x = NSMinX(_seek.frame) + 6 + (NSWidth(_seek.frame) - 12) * value - width / 2;
  _seekBubble.frame = NSMakeRect(std::max<CGFloat>(4, std::min<CGFloat>(x, NSWidth(self.bounds) - width - 4)),
                                 NSMinY(_seek.frame) - 22,
                                 width, 18);
}

- (void)flashSymbol:(NSString*)symbol text:(NSString*)text {
  NSImage* image = symbol ? [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil] : nil;
  _flashImage.image = [image
      imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:text ? 22 : 28
                                                                                    weight:NSFontWeightSemibold]];
  _flashImage.frame = text ? NSMakeRect(18, 12, 40, 30) : NSMakeRect(18, 18, 40, 40);
  _flashText.stringValue = text ?: @"";
  _flashText.hidden = !text;
  [_flash.layer removeAllAnimations];
  _flash.alphaValue = 1;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
    context.duration = 0.6;
    context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    self->_flash.animator.alphaValue = 0;
  }];
}

#pragma mark Keyboard

// YouTube's keys: space or k plays and pauses, j and l skip 10 seconds, the arrows skip 5 seconds or change the
// volume, m mutes, f returns to the tab, 0–9 jump through the video and < and > change the speed.
- (BOOL)handleKey:(NSEvent*)event {
  if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption))
    return NO;
  NSString* key = event.charactersIgnoringModifiers.lowercaseString;
  if (key.length != 1) return NO;
  const unichar c = [key characterAtIndex:0];
  NSString* typed = event.characters;
  const unichar shifted = typed.length == 1 ? [typed characterAtIndex:0] : 0;
  if (c == ' ' || c == 'k') {
    [self togglePlay:nil];
  } else if (c == 'f') {
    [self backToTab:nil];
  } else if (!_available) {
    return NO;
  } else if (c == 'j' || c == 'l' || c == NSLeftArrowFunctionKey || c == NSRightArrowFunctionKey) {
    const double seconds = c == 'j' ? -10 : c == 'l' ? 10 : c == NSLeftArrowFunctionKey ? -5 : 5;
    [self seekBy:seconds];
    [self flashSymbol:[NSString stringWithFormat:@"%@.%d", seconds < 0 ? @"gobackward" : @"goforward",
                                                 static_cast<int>(std::abs(seconds))]
                 text:nil];
  } else if (c == NSUpArrowFunctionKey || c == NSDownArrowFunctionKey) {
    const double volume = std::clamp((_muted ? 0 : _volume) + (c == NSUpArrowFunctionKey ? 0.05 : -0.05), 0.0, 1.0);
    _volume = volume;
    _muted = volume == 0;
    _volumeBar.value = volume;
    [self updateVolume];
    [self send:BoazPiPActionSetVolume value:volume];
    [self flashSymbol:volume == 0 ? @"speaker.slash.fill" : @"speaker.wave.2.fill"
                 text:[NSString stringWithFormat:@"%d%%", static_cast<int>(std::lround(volume * 100))]];
  } else if (c == 'm') {
    [self toggleMute:nil];
    [self flashSymbol:_muted ? @"speaker.slash.fill" : @"speaker.wave.2.fill" text:nil];
  } else if (c >= '0' && c <= '9' && _duration > 0) {
    _lastSeek = CACurrentMediaTime();
    _current = _duration * (c - '0') / 10.0;
    _seek.value = _current / _duration;
    [self updateTime];
    [self send:BoazPiPActionSeekFraction value:(c - '0') / 10.0];
  } else if (shifted == '<' || shifted == '>') {
    // The next listed speed up or down from the current one, which may be a speed the page chose itself.
    const double current = _rate;
    size_t at = 0;
    while (at < kRates.size() && kRates[at] < current - 0.001) ++at;
    if (shifted == '<') at = at == 0 ? 0 : at - 1;
    else if (at < kRates.size() && std::abs(kRates[at] - current) < 0.001) ++at;
    const double rate = kRates[std::min(at, kRates.size() - 1)];
    [self setRate:rate];
    [self flashSymbol:nil text:RateText(rate)];
  } else {
    return NO;
  }
  _active = YES;
  [self updateChromeVisibility];
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(becameIdle) object:nil];
  [self performSelector:@selector(becameIdle) withObject:nil afterDelay:2.5];
  return YES;
}
@end

namespace boaz {
namespace {
// The state of the page's Picture in Picture video, read from an isolated world. Numbers only, so the result needs no
// further checks: paused, current time, duration (-1 when live), end of the buffered range, volume, muted, rate.
constexpr char16_t kStateScript[] =
    uR"((() => {
  const v = document.pictureInPictureElement;
  if (!(v instanceof HTMLMediaElement)) return null;
  let buffered = 0;
  for (let i = 0; i < v.buffered.length; i++)
    if (v.buffered.start(i) <= v.currentTime + 1) buffered = Math.max(buffered, v.buffered.end(i));
  return [v.paused ? 1 : 0, v.currentTime || 0, isFinite(v.duration) ? v.duration : -1, buffered,
          v.volume, v.muted ? 1 : 0, v.playbackRate];
})())";

double Number(const base::ListValue& list, size_t index) {
  return list[index].GetIfDouble().value_or(0);
}

class Controls final : public views::WidgetObserver {
 public:
  Controls(views::Widget* widget, content::VideoPictureInPictureWindowController* controller,
           base::RepeatingCallback<bool()> overlay_shown)
      : widget_(widget), controller_(controller), overlay_shown_(std::move(overlay_shown)) {
    observation_.Observe(widget);
    NSWindow* window = widget->GetNativeWindow().GetNativeNSWindow();
    NSView* host_view = window.contentView;
    view_ = [[BoazPiPControlsView alloc] initWithFrame:host_view.bounds];
    base::WeakPtr<Controls> weak = weak_factory_.GetWeakPtr();
    view_.handler = ^(BoazPiPAction action, double value) {
      if (weak) weak->Run(action, value);
    };
    [host_view addSubview:view_ positioned:NSWindowAbove relativeTo:nil];
    __weak BoazPiPControlsView* view = view_;
    key_monitor_ = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                         handler:^NSEvent*(NSEvent* event) {
                                                           if (!view || event.window != view.window) return event;
                                                           return [view handleKey:event] ? nil : event;
                                                         }];
    space_observer_ = [NSWorkspace.sharedWorkspace.notificationCenter
        addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (weak) weak->FollowActiveSpace();
                }];
    ApplyWindowBehavior();
    timer_.Start(FROM_HERE, base::Milliseconds(250), base::BindRepeating(&Controls::Poll, weak));
  }
  ~Controls() override {
    timer_.Stop();
    if (key_monitor_) [NSEvent removeMonitor:key_monitor_];
    if (space_observer_) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:space_observer_];
    [view_ stop];
    [view_ removeFromSuperview];
  }

 private:
  void OnWidgetVisibilityChanged(views::Widget*, bool visible) override {
    if (!visible) return;
    ApplyWindowBehavior();
    FollowActiveSpace();
  }

  // A window on every Space still stays out of other apps' full-screen Spaces until it is moved into one, as
  // Chromium does for its own floating windows. Wait for the switch to settle, then check.
  void FollowActiveSpace() {
    follow_timer_.Start(FROM_HERE, base::Milliseconds(300), base::BindOnce(&Controls::JoinActiveSpace,
                                                                          weak_factory_.GetWeakPtr()));
  }
  void JoinActiveSpace() {
    if (!widget_->IsVisible()) return;
    NSWindow* window = widget_->GetNativeWindow().GetNativeNSWindow();
    CFArrayRef info = CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow,
                                                 static_cast<CGWindowID>(window.windowNumber));
    NSArray* windows = CFBridgingRelease(info);
    NSDictionary* entry = windows.firstObject;
    if ([entry[(__bridge NSString*)kCGWindowIsOnscreen] boolValue]) return;
    widget_->MoveToActiveFullscreenSpace();
  }
  void OnWidgetDestroying(views::Widget*) override {
    observation_.Reset();
    delete this;
  }

  // Above every window, on every Space, including over full-screen apps, whichever app is active.
  void ApplyWindowBehavior() {
    NSWindow* window = widget_->GetNativeWindow().GetNativeNSWindow();
    NSWindowCollectionBehavior behavior = window.collectionBehavior;
    behavior &= ~(NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenPrimary |
                  NSWindowCollectionBehaviorFullScreenNone | NSWindowCollectionBehaviorPrimary);
    behavior |= NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    window.collectionBehavior = behavior;
    window.hidesOnDeactivate = NO;
    if (window.level < NSFloatingWindowLevel) window.level = NSFloatingWindowLevel;
  }

  void Poll() {
    view_.suppressed = overlay_shown_.Run();
    if (pending_ > 0) return;
    auto* contents = controller_->GetWebContents();
    if (!contents) return;
    if (auto* frame = content::RenderFrameHost::FromID(media_frame_); frame && frame->IsRenderFrameLive()) {
      Query(frame, 1);
      return;
    }
    media_frame_ = {};
    std::vector<content::RenderFrameHost*> frames;
    contents->ForEachRenderFrameHost([&](content::RenderFrameHost* frame) {
      if (frame->IsActive() && frame->IsRenderFrameLive()) frames.push_back(frame);
    });
    for (auto* frame : frames) Query(frame, frames.size());
    if (frames.empty()) [view_ setMediaAvailable:NO playing:controller_->IsPlayerActive()];
  }

  void Query(content::RenderFrameHost* frame, size_t round) {
    if (pending_ == 0) {
      pending_ = round;
      found_ = false;
    }
    // A frame that goes away without answering still counts as an answer.
    frame->ExecuteJavaScriptInIsolatedWorld(
        kStateScript,
        mojo::WrapCallbackWithDefaultInvokeIfNotRun(
            base::BindOnce(&Controls::OnState, weak_factory_.GetWeakPtr(), frame->GetGlobalId()), base::Value()),
        ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }

  void OnState(content::GlobalRenderFrameHostId frame, base::Value value) {
    if (pending_ > 0) --pending_;
    const auto* list = value.GetIfList();
    if (list && list->size() == 7) {
      found_ = true;
      media_frame_ = frame;
      [view_ setPaused:Number(*list, 0) != 0
               current:Number(*list, 1)
              duration:Number(*list, 2)
              buffered:Number(*list, 3)
                volume:Number(*list, 4)
                 muted:Number(*list, 5) != 0
                  rate:Number(*list, 6)];
    } else if (frame == media_frame_) {
      media_frame_ = {};
    }
    if (pending_ == 0 && !found_) [view_ setMediaAvailable:NO playing:controller_->IsPlayerActive()];
  }

  void Execute(const std::string& statement) {
    auto* frame = content::RenderFrameHost::FromID(media_frame_);
    if (!frame || !frame->IsRenderFrameLive()) return;
    const std::string script =
        "(() => { const v = document.pictureInPictureElement; if (!(v instanceof HTMLMediaElement)) return;"
        " const clamp = t => Math.max(0, isFinite(v.duration) ? Math.min(v.duration, t) : t); " +
        statement + " })()";
    frame->ExecuteJavaScriptInIsolatedWorld(base::UTF8ToUTF16(script), base::NullCallback(),
                                            ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }

  void Run(BoazPiPAction action, double value) {
    const std::string number = base::NumberToString(std::isfinite(value) ? value : 0);
    switch (action) {
      case BoazPiPActionTogglePlay:
        controller_->TogglePlayPause();
        break;
      case BoazPiPActionSeekTo:
        Execute("v.currentTime = clamp(" + number + ");");
        break;
      case BoazPiPActionSeekBy:
        Execute("v.currentTime = clamp(v.currentTime + " + number + ");");
        break;
      case BoazPiPActionSeekFraction:
        Execute("if (isFinite(v.duration)) v.currentTime = v.duration * " + number + ";");
        break;
      case BoazPiPActionSetVolume:
        Execute("v.volume = Math.max(0, Math.min(1, " + number + ")); v.muted = v.volume === 0;");
        break;
      case BoazPiPActionToggleMute:
        Execute("v.muted = !v.muted; if (!v.muted && v.volume === 0) v.volume = 0.5;");
        break;
      case BoazPiPActionSetRate:
        Execute("v.playbackRate = " + number + ";");
        break;
      case BoazPiPActionBackToTab:
      case BoazPiPActionClose:
        // Closing destroys this view; leave the AppKit event that asked for it first.
        base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
            FROM_HERE, base::BindOnce(&Controls::CloseWindow, weak_factory_.GetWeakPtr(),
                                      action == BoazPiPActionBackToTab));
        break;
    }
  }

  void CloseWindow(bool back_to_tab) {
    if (back_to_tab) {
      controller_->CloseAndFocusInitiator();
      return;
    }
    PictureInPictureWindowManager::GetInstance()->ExitPictureInPictureViaWindowUi(
        PictureInPictureWindowManager::UiBehavior::kCloseWindowAndPauseVideo);
  }

  raw_ptr<views::Widget> widget_;
  raw_ptr<content::VideoPictureInPictureWindowController> controller_;
  base::RepeatingCallback<bool()> overlay_shown_;
  base::ScopedObservation<views::Widget, views::WidgetObserver> observation_{this};
  BoazPiPControlsView* __strong view_ = nil;
  id __strong key_monitor_ = nil;
  id __strong space_observer_ = nil;
  base::OneShotTimer follow_timer_;
  base::RepeatingTimer timer_;
  content::GlobalRenderFrameHostId media_frame_;
  size_t pending_ = 0;
  bool found_ = false;
  base::WeakPtrFactory<Controls> weak_factory_{this};
};
}  // namespace

bool NativePictureInPictureControlsEnabled() { return NativeHostEnabled(); }

void AttachNativePictureInPictureControls(views::Widget* window,
                                          content::VideoPictureInPictureWindowController* controller,
                                          base::RepeatingCallback<bool()> overlay_shown) {
  if (!NativePictureInPictureControlsEnabled() || !window || !controller) return;
  new Controls(window, controller, std::move(overlay_shown));
}
}  // namespace boaz
