package com.jlogicsoftware.prudent.local

import io.flutter.embedding.android.FlutterFragmentActivity

// A FragmentActivity because local_auth (zen_ui_lock's owner check, "Forgot PIN?") needs one on
// Android to show the system's biometric prompt.
class MainActivity : FlutterFragmentActivity()
