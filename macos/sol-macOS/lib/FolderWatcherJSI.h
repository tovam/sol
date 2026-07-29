
#pragma once
#include <ReactCommon/CallInvoker.h>
#include <jsi/jsi.h>
#include <react/bridging/CallbackWrapper.h>
#include <memory>
#include <string>
#include <CoreServices/CoreServices.h>

namespace sol {

namespace jsi = facebook::jsi;
namespace react = facebook::react;

class JSI_EXPORT FolderWatcherJSI: public jsi::HostObject {
public:
  FolderWatcherJSI(
      std::string path,
      std::weak_ptr<react::CallbackWrapper> callback,
      std::shared_ptr<react::CallInvoker> jsInvoker);
  ~FolderWatcherJSI();

  void startStream();
  void stopStream();
  void handleWakeNotification();

  std::string path;
  std::weak_ptr<react::CallbackWrapper> callback;
  std::shared_ptr<react::CallInvoker> jsInvoker;
  FSEventStreamRef streamRef = nullptr;
  CFStringRef cfPath = nullptr;
  CFArrayRef pathsToWatch = nullptr;
  id wakeObserver = nil;
};

} // namespace sol
