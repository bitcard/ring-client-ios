/*
 *  Copyright (C) 2018-2019 Savoir-faire Linux Inc.
 *
 *  Author: Andreas Traczyk <andreas.traczyk@savoirfairelinux.com>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA.
 */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVCaptureOutput.h>

@protocol VideoAdapterDelegate;

@interface VideoAdapter : NSObject

@property (class, nonatomic, weak) id <VideoAdapterDelegate> delegate;

- (void)addVideoDeviceWithName:(NSString*)deviceName withDevInfo:(NSDictionary*)deviceInfoDict;
- (void)registerSinkTargetWithSinkId:sinkId withWidth:(NSInteger)w withHeight:(NSInteger)h;
- (void)removeSinkTargetWithSinkId:(NSString*)sinkId;
- (void)writeOutgoingFrameWithImage:(UIImage*)image;
- (void)setDecodingAccelerated:(BOOL)state;
- (void)switchInput:(NSString*)deviceName;

@end
