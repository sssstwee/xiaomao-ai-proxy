import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';

/// Reuses the upstream channel protocol with the HarmonyOS native file picker.
class FilePickerOhos extends FilePickerAndroid {
  static void registerWith() {
    FilePickerPlatform.instance = FilePickerOhos();
  }
}
