#include "FolderWatcherJSI.h"
#include <ReactCommon/CallInvoker.h>
#include <jsi/jsi.h>
#include <memory>
#include <string>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

namespace sol {

namespace jsi = facebook::jsi;
namespace react = facebook::react;

static void FolderWatcherCallback(ConstFSEventStreamRef streamRef,
								  void *clientCallBackInfo,
								  size_t numEvents,
								  void *eventPaths,
								  const FSEventStreamEventFlags eventFlags[],
								  const FSEventStreamEventId eventIds[]) {
	FolderWatcherJSI *watcher = static_cast<FolderWatcherJSI *>(clientCallBackInfo);
	char **paths = (char **)eventPaths;
	for (size_t i = 0; i < numEvents; ++i) {
		std::string pathStr(paths[i]);
		std::string changeType = "modified";
		if ((eventFlags[i] & kFSEventStreamEventFlagItemCreated) != 0) {
			changeType = "created";
		} else if ((eventFlags[i] & kFSEventStreamEventFlagItemRemoved) != 0) {
			changeType = "deleted";
		}
		auto callback = watcher->callback;
		auto jsInvoker = watcher->jsInvoker;
		if (!callback.expired() && jsInvoker) {
			jsInvoker->invokeAsync([callback, pathStr, changeType]() mutable {
				auto lockedCallback = callback.lock();
				if (!lockedCallback) {
					return;
				}

				auto &rt = lockedCallback->runtime();
				lockedCallback->callback().call(
					rt,
					facebook::jsi::String::createFromUtf8(rt, pathStr),
					facebook::jsi::String::createFromUtf8(rt, changeType)
				);
			});
		}
	}
}

FolderWatcherJSI::FolderWatcherJSI(
	std::string path,
	std::weak_ptr<react::CallbackWrapper> callback,
	std::shared_ptr<react::CallInvoker> jsInvoker)
	: path(std::move(path)),
	  callback(std::move(callback)),
	  jsInvoker(std::move(jsInvoker)) {
	cfPath = CFStringCreateWithCString(nullptr, path.c_str(), kCFStringEncodingUTF8);
	pathsToWatch = CFArrayCreate(nullptr, (const void**)&cfPath, 1, &kCFTypeArrayCallBacks);
	startStream();

	// Add observer for system wake notification (capture this pointer safely)
	FolderWatcherJSI *cppThis = this;
	wakeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSWorkspaceDidWakeNotification
		object:nil
		queue:[NSOperationQueue mainQueue]
		usingBlock:^(NSNotification * _Nonnull note) {
			if (cppThis) {
				cppThis->handleWakeNotification();
			}
		}];
}

void FolderWatcherJSI::startStream() {
	stopStream();
	FSEventStreamContext context = {
		0,
		this,
		nullptr,
		nullptr,
		nullptr
	};
	streamRef = FSEventStreamCreate(nullptr,
								   &FolderWatcherCallback,
								   &context,
								   pathsToWatch,
								   kFSEventStreamEventIdSinceNow,
								   0.5,
								   kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer);
	if (streamRef) {
		FSEventStreamScheduleWithRunLoop(streamRef, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
		FSEventStreamStart(streamRef);
	}
}

void FolderWatcherJSI::stopStream() {
	if (streamRef) {
		FSEventStreamStop(streamRef);
		FSEventStreamInvalidate(streamRef);
		FSEventStreamRelease(streamRef);
		streamRef = nullptr;
	}
}

void FolderWatcherJSI::handleWakeNotification() {
	// Restart the FSEventStream after wake
  NSLog(@"🟩 Restarting FSEventStream");
	startStream();
}

FolderWatcherJSI::~FolderWatcherJSI() {
	stopStream();
	auto callbackToRelease = callback;
	if (!callbackToRelease.expired() && jsInvoker) {
		jsInvoker->invokeAsync([callbackToRelease]() mutable {
			auto lockedCallback = callbackToRelease.lock();
			if (lockedCallback) {
				lockedCallback->destroy();
			}
		});
	}
	callback.reset();
	if (wakeObserver) {
		[[NSNotificationCenter defaultCenter] removeObserver:wakeObserver];
		wakeObserver = nil;
	}
	if (cfPath) {
		CFRelease(cfPath);
		cfPath = nullptr;
	}
	if (pathsToWatch) {
		CFRelease(pathsToWatch);
		pathsToWatch = nullptr;
	}
}


} // namespace sol
