package io.invertase.firebase.storage;

import android.support.annotation.RequiresPermission;

import com.facebook.react.ReactPackage;
import com.facebook.react.bridge.JavaScriptModule;
import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.uimanager.UIManagerModule;
import com.facebook.react.uimanager.ViewManager;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

@SuppressWarnings("unused")
public class RNFirebaseStoragePackage implements ReactPackage {
  @RequiresPermission(
    allOf = {"android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE", "android.permission.READ_EXTERNAL_STORAGE", "android.permission.WRITE_EXTERNAL_STORAGE"}
  )
  public RNFirebaseStoragePackage() {
  }

  /**
   * @param reactContext react application context that can be used to create modules
   * @return list of native modules to register with the newly created catalyst instance
   */
  @Override
  public List<NativeModule> createNativeModules(ReactApplicationContext reactContext) {
    List<NativeModule> modules = new ArrayList<>();
    modules.add(new RNFirebaseStorage(reactContext));

    return modules;
  }

  /**
   * @param reactContext
   * @return a list of view managers that should be registered with {@link UIManagerModule}
   */
  @Override
  public List<ViewManager> createViewManagers(ReactApplicationContext reactContext) {
    return Collections.emptyList();
  }
}
