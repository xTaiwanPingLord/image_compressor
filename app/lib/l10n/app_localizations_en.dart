// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Image Compressor';

  @override
  String get navNormal => 'General';

  @override
  String get navEcommerce => 'E-commerce';

  @override
  String get navSettings => 'Settings';

  @override
  String get close => 'Close';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get continueAction => 'Continue';

  @override
  String get gotIt => 'Got it';

  @override
  String get resetDefaults => 'Reset to defaults';

  @override
  String get openFolder => 'Open folder';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get addImages => 'Add images';

  @override
  String get addFolder => 'Add folder';

  @override
  String get addFolderRecursive => 'Add folder (including subfolders)';

  @override
  String get remove => 'Remove';

  @override
  String get dropHere => 'Drop images or folders here';

  @override
  String get imagesTypeLabel => 'Images';

  @override
  String get pad => 'Pad';

  @override
  String get crop => 'Crop';

  @override
  String get unreadable => 'Unreadable';

  @override
  String get unknownError => 'Unknown error';

  @override
  String get runFailed => 'Failed';

  @override
  String get blockRunning => 'Running';

  @override
  String get blockNoImages => 'Add some images first';

  @override
  String get blockNoName => 'Enter a name';

  @override
  String get blockBadName => 'Name can\'t contain \\ / : * ? \" < > |';

  @override
  String get blockNoPlatform => 'Select at least one platform';

  @override
  String get blockLoading => 'Reading image info';

  @override
  String get blockUnreadable => 'Some images can\'t be read; remove them first';

  @override
  String get errIo => 'File access error';

  @override
  String get errDecode => 'Can\'t read image';

  @override
  String get errEncode => 'Encoding failed';

  @override
  String get errInvalid => 'Invalid settings';

  @override
  String get errTrash => 'Couldn\'t move to trash';

  @override
  String get errOther => 'Error';

  @override
  String warnOverMax(int quality, String size, String max) {
    return 'Still $size at quality $quality, over the $max limit';
  }

  @override
  String warnDownscaled(int quality, int times, int width, int height) {
    return 'Still too large at quality $quality; resolution reduced $times× to $width×$height';
  }

  @override
  String warnUnderMin(String size, String min) {
    return 'File is $size, below the $min minimum (already quality 100, 4:4:4, no optimization)';
  }

  @override
  String get warnGifFirstFrame => 'Only the first GIF frame is used';

  @override
  String get warnJpegReencoded =>
      'JPEG had to be re-encoded (resize or conversion); saved at quality 100, 4:4:4';

  @override
  String warnTargetNotReached(String size, String target) {
    return 'Still $size at quality 1, over the $target target';
  }

  @override
  String get ecomNameHint => 'e.g. 223_ssd';

  @override
  String get ecomRun => 'Run';

  @override
  String get ecomClearAll => 'Clear all';

  @override
  String ecomEncoding(int done, int total) {
    return 'Compressing $done / $total';
  }

  @override
  String get ecomWriting => 'Writing files…';

  @override
  String get ecomPreparing => 'Reading and laying out…';

  @override
  String ecomStatus(
    int count,
    int shopee,
    int momo,
    String smart,
    String width,
    int quality,
  ) {
    return '$count images · Detail limit Shopee $shopee / momo $momo · Smart cut $smart · Shopee max width $width · Max quality $quality';
  }

  @override
  String get on => 'on';

  @override
  String get off => 'off';

  @override
  String get unlimited => 'unlimited';

  @override
  String get catMain => 'Main';

  @override
  String get catVariant => 'Variants';

  @override
  String get catDesc => 'Details';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images',
      one: '1 image',
    );
    return '$_temp0';
  }

  @override
  String get clearSection => 'Clear this section';

  @override
  String get enterNumber => 'Enter a number';

  @override
  String rangeHelp(int min, int max) {
    return '$min–$max';
  }

  @override
  String rangeError(int min, int max) {
    return 'Must be $min–$max';
  }

  @override
  String get ecomSettingsTitle => 'E-commerce settings';

  @override
  String get ecomShopeeMaxDesc => 'Shopee max detail images';

  @override
  String get ecomMomoMaxDesc => 'momo max detail images';

  @override
  String ecomMomoMaxDescHelp(int min, int max) {
    return '$min–$max (default 18, leaving room for store info images)';
  }

  @override
  String get ecomShopeeMaxWidth => 'Shopee max width (px)';

  @override
  String get ecomShopeeMaxWidthHelp =>
      '0 = no limit; Shopee displays up to about 1750';

  @override
  String get ecomShopeeMaxWidthError => 'Must be 0 or ≥ 750';

  @override
  String get ecomMomoMinLast => 'momo detail last-segment min height (px)';

  @override
  String get ecomMomoMinLastHelp =>
      'Shorter tails borrow height from the previous segment; 0 = keep actual height';

  @override
  String get ecomMomoMinLastError => 'Must be less than 1500';

  @override
  String get ecomQuality => 'Quality';

  @override
  String get ecomQualityHelp =>
      'Each image gets the highest quality that fits its size limit, capped below';

  @override
  String get ecomMaxQuality => 'Max quality';

  @override
  String get ecomChroma444 => '4:4:4 chroma';

  @override
  String get ecomChroma444Help =>
      'Sharper text and thin lines (especially red text); larger files';

  @override
  String get ecomSmartCut => 'Smart cut';

  @override
  String get ecomSmartCutHelp =>
      'Cut at the most uniform row within 150px above each split to avoid cutting through text';

  @override
  String get ecomDefaultFit => 'Default for new images';

  @override
  String get ecomOverflowTitle => 'Too many detail images';

  @override
  String ecomOverflowLine(String platform, int count, int limit) {
    return '$platform: would produce $count images, limit is $limit';
  }

  @override
  String get ecomOverflowHelp =>
      'Nothing was written. Remove some detail images or raise the limit in settings, then try again.';

  @override
  String ecomResultTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wrote $count files',
      one: 'Wrote 1 file',
    );
    return '$_temp0';
  }

  @override
  String ecomDisposed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Moved $count old files to the trash',
      one: 'Moved 1 old file to the trash',
    );
    return '$_temp0';
  }

  @override
  String ecomWarnCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files have warnings',
      one: '1 file has warnings',
    );
    return '$_temp0';
  }

  @override
  String get overwriteTitle => 'Overwrite originals?';

  @override
  String get overwriteBody =>
      'The output folder is the same as the originals and there\'s no suffix. Originals will be moved to the trash before the compressed files are written. Continue?';

  @override
  String normalDone(int count) {
    return '$count done';
  }

  @override
  String normalKept(int count) {
    return '$count kept original';
  }

  @override
  String normalFailedCount(int count) {
    return '$count failed';
  }

  @override
  String get listSep => ', ';

  @override
  String sizeChange(String before, String after, String pct) {
    return '$before → $after (−$pct%)';
  }

  @override
  String get compressAll => 'Compress all';

  @override
  String compressSelected(int count) {
    return 'Compress selected ($count)';
  }

  @override
  String get clearAll => 'Clear all';

  @override
  String removeSelected(int count) {
    return 'Remove selected ($count)';
  }

  @override
  String normalStatusIdle(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images',
      one: '1 image',
    );
    return '$_temp0 · $size';
  }

  @override
  String normalStatusLast(String change) {
    return 'Last run: $change';
  }

  @override
  String get colName => 'Name';

  @override
  String get colOriginalSize => 'Original';

  @override
  String get colNewSize => 'New';

  @override
  String get colResolution => 'Resolution';

  @override
  String get colSaving => 'Saved';

  @override
  String get colStatus => 'Status';

  @override
  String get statusWorking => 'Working…';

  @override
  String get statusDone => 'Done';

  @override
  String get statusKept => 'Kept original';

  @override
  String get statusFailed => 'Failed';

  @override
  String get previewSelectHint => 'Select an image to preview';

  @override
  String get previewOriginal => 'Original';

  @override
  String get previewCompressed => 'Compressed';

  @override
  String previewEstimate(String size, String change) {
    return 'Est. $size ($change%)';
  }

  @override
  String get lossless => 'Lossless';

  @override
  String previewFailed(String error) {
    return 'Can\'t preview: $error';
  }

  @override
  String get tabCompression => 'Compression';

  @override
  String get tabOutput => 'Output';

  @override
  String get secMode => 'Mode';

  @override
  String get modeQuality => 'Quality';

  @override
  String get modeTargetSize => 'Target size';

  @override
  String get losslessHelp =>
      'JPEG: re-optimize only; PNG: oxipng; WebP: lossless mode';

  @override
  String get chromaSubsampling => 'Chroma subsampling';

  @override
  String get chromaAuto => 'Auto (4:4:4 at quality ≥ 90)';

  @override
  String get chroma444 => '4:4:4 (sharpest)';

  @override
  String get chroma420 => '4:2:0 (smallest)';

  @override
  String get pngOptimize => 'Optimize';

  @override
  String get pngOptimizeHelp =>
      'Higher levels are smaller but slower; lossy PNG uses quality to set the palette size';

  @override
  String get secResize => 'Resize';

  @override
  String get resizeMethod => 'Resize method';

  @override
  String get resizeNone => 'No resizing';

  @override
  String get resizePercentage => 'Percentage';

  @override
  String get resizeWidth => 'Fixed width';

  @override
  String get resizeHeight => 'Fixed height';

  @override
  String get resizeLongEdge => 'Long edge';

  @override
  String get resizeShortEdge => 'Short edge';

  @override
  String get resizeFitBox => 'Fit in box (width × height)';

  @override
  String get valueWidth => 'Width';

  @override
  String get valueHeight => 'Height';

  @override
  String get valueMaxWidth => 'Max width';

  @override
  String get valueMaxHeight => 'Max height';

  @override
  String get noEnlarge => 'Don\'t enlarge';

  @override
  String get noEnlargeHelp => 'Images smaller than the target keep their size';

  @override
  String get resizeNote => 'Always keeps aspect ratio (Lanczos3)';

  @override
  String get secFormat => 'Format';

  @override
  String get outputFormat => 'Output format';

  @override
  String get formatSame => 'Same as original (BMP / TIFF / GIF → PNG)';

  @override
  String get secLocation => 'Location';

  @override
  String get sameFolder => 'Same folder as original';

  @override
  String get customFolder => 'Choose a folder';

  @override
  String get openGallery => 'Open Photos';

  @override
  String get ecomGalleryAlbums => 'Shopee and momo albums';

  @override
  String get saveToGallery => 'Save to Photos';

  @override
  String saveToGalleryHelp(String album) {
    return 'Saved to the “$album” album';
  }

  @override
  String get errGalleryDenied =>
      'No access to Photos: allow it for this app in system Settings';

  @override
  String get change => 'Change…';

  @override
  String get keepStructure => 'Keep folder structure';

  @override
  String get keepStructureHelp =>
      'When a folder is added, mirror its subfolders';

  @override
  String get secFileName => 'File name';

  @override
  String get suffix => 'Suffix';

  @override
  String get overwriteWarning =>
      'Same folder with no suffix overwrites originals (they go to the trash first)';

  @override
  String get secMetadata => 'Metadata';

  @override
  String get keepMetadata => 'Keep EXIF and other metadata';

  @override
  String get keepMetadataHelp => 'ICC color profiles are always kept';

  @override
  String get keepDates => 'Keep file dates';

  @override
  String get secOther => 'Other';

  @override
  String get skipIfBigger => 'Keep original if the result is larger';

  @override
  String get skipIfBiggerHelp =>
      'When format and size are unchanged, write the original instead';

  @override
  String get setLanguage => 'Language';

  @override
  String get setTheme => 'Theme';

  @override
  String get themeSystem => 'Auto';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get setColor => 'Color';

  @override
  String get colorFollowSystem => 'Use system color';

  @override
  String get colorFollowSystemHelp =>
      'Wallpaper colors on Android 12+; accent color on Windows / macOS';

  @override
  String get setFont => 'Font';

  @override
  String get fontDefault => 'Default (system font)';

  @override
  String get fontSample => 'Image Compressor 圖片壓縮 0123';

  @override
  String get setAbout => 'About';

  @override
  String get aboutFontCredit =>
      'Bundled fonts: MiSans, MiSans TC (Xiaomi MiSans, free for commercial use)';

  @override
  String get colonSep => ': ';

  @override
  String get heicUnsupportedShort => 'HEIC not supported';

  @override
  String get errHeifWindows =>
      'This PC can\'t read HEIC: install \"HEIF Image Extensions\" and \"HEVC Video Extensions\" from the Microsoft Store';

  @override
  String get errHeifLinux =>
      'Can\'t read HEIC: install libheif1 and libheif-plugin-libde265';

  @override
  String get errHeifAndroid =>
      'This device can\'t read HEIC (requires Android 11 or later)';

  @override
  String get errHeifOther => 'HEIC isn\'t supported on this platform yet';

  @override
  String get aboutHeicOk => 'HEIC: supported (system decoder)';

  @override
  String get aboutHeicNo => 'HEIC: not available';

  @override
  String get blockNoOutputFolder => 'Choose an output folder';

  @override
  String get blockNeedOutputFolder =>
      'Some images weren\'t added from a folder; choose a folder under Output';

  @override
  String get chooseOutputFolder => 'Choose output folder';

  @override
  String outputTo(String name) {
    return 'Output to: $name';
  }

  @override
  String sharedToWhich(int count) {
    return 'Add $count images to which section?';
  }

  @override
  String get overwriteBodyAndroid =>
      'The output folder is the same as the originals and there\'s no suffix. Originals will be moved to an _old subfolder before the compressed files are written. Continue?';

  @override
  String get overwriteWarningAndroid =>
      'Same folder with no suffix overwrites originals (they\'re moved to _old first)';

  @override
  String get ecomPlatforms => 'Platforms';

  @override
  String get pickFromGallery => 'Choose from gallery';

  @override
  String get pickFromFiles => 'Choose from files (browse folders)';

  @override
  String get warnExifThumbnailRemoved =>
      'EXIF exceeded JPEG\'s 64 KB limit; its thumbnail was removed';

  @override
  String get warnExifDropped =>
      'EXIF exceeded JPEG\'s 64 KB limit and wasn\'t kept';
}
