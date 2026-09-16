import 'package:flutter/material.dart';

/// Global navigator key so services outside the widget tree (FCM tap
/// handlers, background message routing) can push routes.
final rootNavigatorKey = GlobalKey<NavigatorState>();
