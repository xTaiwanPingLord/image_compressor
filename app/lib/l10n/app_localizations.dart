import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'CN'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'圖片壓縮'**
  String get appTitle;

  /// No description provided for @navNormal.
  ///
  /// In zh, this message translates to:
  /// **'普通'**
  String get navNormal;

  /// No description provided for @navEcommerce.
  ///
  /// In zh, this message translates to:
  /// **'電商'**
  String get navEcommerce;

  /// No description provided for @navSettings.
  ///
  /// In zh, this message translates to:
  /// **'設定'**
  String get navSettings;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'關閉'**
  String get close;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'儲存'**
  String get save;

  /// No description provided for @continueAction.
  ///
  /// In zh, this message translates to:
  /// **'繼續'**
  String get continueAction;

  /// No description provided for @gotIt.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get gotIt;

  /// No description provided for @resetDefaults.
  ///
  /// In zh, this message translates to:
  /// **'還原預設'**
  String get resetDefaults;

  /// No description provided for @openFolder.
  ///
  /// In zh, this message translates to:
  /// **'開啟資料夾'**
  String get openFolder;

  /// No description provided for @settingsTooltip.
  ///
  /// In zh, this message translates to:
  /// **'設定'**
  String get settingsTooltip;

  /// No description provided for @addImages.
  ///
  /// In zh, this message translates to:
  /// **'加入圖片'**
  String get addImages;

  /// No description provided for @addFolder.
  ///
  /// In zh, this message translates to:
  /// **'加入資料夾'**
  String get addFolder;

  /// No description provided for @addFolderRecursive.
  ///
  /// In zh, this message translates to:
  /// **'加入資料夾（含子資料夾）'**
  String get addFolderRecursive;

  /// No description provided for @remove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get remove;

  /// No description provided for @dropHere.
  ///
  /// In zh, this message translates to:
  /// **'拖放圖片或資料夾到這裡'**
  String get dropHere;

  /// No description provided for @imagesTypeLabel.
  ///
  /// In zh, this message translates to:
  /// **'圖片'**
  String get imagesTypeLabel;

  /// No description provided for @pad.
  ///
  /// In zh, this message translates to:
  /// **'補白'**
  String get pad;

  /// No description provided for @crop.
  ///
  /// In zh, this message translates to:
  /// **'裁切'**
  String get crop;

  /// No description provided for @unreadable.
  ///
  /// In zh, this message translates to:
  /// **'無法讀取'**
  String get unreadable;

  /// No description provided for @unknownError.
  ///
  /// In zh, this message translates to:
  /// **'未知錯誤'**
  String get unknownError;

  /// No description provided for @runFailed.
  ///
  /// In zh, this message translates to:
  /// **'執行失敗'**
  String get runFailed;

  /// No description provided for @blockRunning.
  ///
  /// In zh, this message translates to:
  /// **'執行中'**
  String get blockRunning;

  /// No description provided for @blockNoImages.
  ///
  /// In zh, this message translates to:
  /// **'請先加入圖片'**
  String get blockNoImages;

  /// No description provided for @blockNoName.
  ///
  /// In zh, this message translates to:
  /// **'請輸入 name'**
  String get blockNoName;

  /// No description provided for @blockBadName.
  ///
  /// In zh, this message translates to:
  /// **'name 不能包含 \\ / : * ? \" < > |'**
  String get blockBadName;

  /// No description provided for @blockNoPlatform.
  ///
  /// In zh, this message translates to:
  /// **'請至少勾選一個平台'**
  String get blockNoPlatform;

  /// No description provided for @blockLoading.
  ///
  /// In zh, this message translates to:
  /// **'讀取圖片資訊中'**
  String get blockLoading;

  /// No description provided for @blockUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'有無法讀取的圖片，請先移除'**
  String get blockUnreadable;

  /// No description provided for @errIo.
  ///
  /// In zh, this message translates to:
  /// **'檔案存取錯誤'**
  String get errIo;

  /// No description provided for @errDecode.
  ///
  /// In zh, this message translates to:
  /// **'無法讀取圖片'**
  String get errDecode;

  /// No description provided for @errEncode.
  ///
  /// In zh, this message translates to:
  /// **'編碼失敗'**
  String get errEncode;

  /// No description provided for @errInvalid.
  ///
  /// In zh, this message translates to:
  /// **'設定錯誤'**
  String get errInvalid;

  /// No description provided for @errTrash.
  ///
  /// In zh, this message translates to:
  /// **'移到垃圾桶失敗'**
  String get errTrash;

  /// No description provided for @errOther.
  ///
  /// In zh, this message translates to:
  /// **'錯誤'**
  String get errOther;

  /// No description provided for @warnOverMax.
  ///
  /// In zh, this message translates to:
  /// **'品質降到 {quality} 仍有 {size}，超過上限 {max}'**
  String warnOverMax(int quality, String size, String max);

  /// No description provided for @warnDownscaled.
  ///
  /// In zh, this message translates to:
  /// **'品質降到 {quality} 仍超標，解析度縮小 {times} 次至 {width}×{height}'**
  String warnDownscaled(int quality, int times, int width, int height);

  /// No description provided for @warnUnderMin.
  ///
  /// In zh, this message translates to:
  /// **'檔案 {size} 低於下限 {min}（已用品質 100、4:4:4 並關閉最佳化）'**
  String warnUnderMin(String size, String min);

  /// No description provided for @warnGifFirstFrame.
  ///
  /// In zh, this message translates to:
  /// **'GIF 只取第一格'**
  String get warnGifFirstFrame;

  /// No description provided for @warnJpegReencoded.
  ///
  /// In zh, this message translates to:
  /// **'JPEG 需重新編碼（縮放或轉檔），以品質 100、4:4:4 輸出'**
  String get warnJpegReencoded;

  /// No description provided for @warnTargetNotReached.
  ///
  /// In zh, this message translates to:
  /// **'品質降到 1 仍有 {size}，超過目標 {target}'**
  String warnTargetNotReached(String size, String target);

  /// No description provided for @ecomNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如 223_ssd'**
  String get ecomNameHint;

  /// No description provided for @ecomRun.
  ///
  /// In zh, this message translates to:
  /// **'執行'**
  String get ecomRun;

  /// No description provided for @ecomClearAll.
  ///
  /// In zh, this message translates to:
  /// **'全部清空'**
  String get ecomClearAll;

  /// No description provided for @ecomEncoding.
  ///
  /// In zh, this message translates to:
  /// **'壓縮中 {done} / {total}'**
  String ecomEncoding(int done, int total);

  /// No description provided for @ecomWriting.
  ///
  /// In zh, this message translates to:
  /// **'寫入檔案…'**
  String get ecomWriting;

  /// No description provided for @ecomPreparing.
  ///
  /// In zh, this message translates to:
  /// **'讀取與排版…'**
  String get ecomPreparing;

  /// No description provided for @ecomStatus.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 張 · 詳情圖上限 Shopee {shopee} / momo {momo} · 智慧切點{smart} · Shopee 最大寬 {width} · 品質上限 {quality}'**
  String ecomStatus(
    int count,
    int shopee,
    int momo,
    String smart,
    String width,
    int quality,
  );

  /// No description provided for @on.
  ///
  /// In zh, this message translates to:
  /// **'開'**
  String get on;

  /// No description provided for @off.
  ///
  /// In zh, this message translates to:
  /// **'關'**
  String get off;

  /// No description provided for @unlimited.
  ///
  /// In zh, this message translates to:
  /// **'不限'**
  String get unlimited;

  /// No description provided for @catMain.
  ///
  /// In zh, this message translates to:
  /// **'主圖'**
  String get catMain;

  /// No description provided for @catVariant.
  ///
  /// In zh, this message translates to:
  /// **'選項圖'**
  String get catVariant;

  /// No description provided for @catDesc.
  ///
  /// In zh, this message translates to:
  /// **'詳情圖'**
  String get catDesc;

  /// No description provided for @imageCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 張'**
  String imageCount(int count);

  /// No description provided for @clearSection.
  ///
  /// In zh, this message translates to:
  /// **'清空此區'**
  String get clearSection;

  /// No description provided for @enterNumber.
  ///
  /// In zh, this message translates to:
  /// **'請輸入數字'**
  String get enterNumber;

  /// No description provided for @rangeHelp.
  ///
  /// In zh, this message translates to:
  /// **'{min}–{max}'**
  String rangeHelp(int min, int max);

  /// No description provided for @rangeError.
  ///
  /// In zh, this message translates to:
  /// **'需在 {min}–{max}'**
  String rangeError(int min, int max);

  /// No description provided for @ecomSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'電商模式設定'**
  String get ecomSettingsTitle;

  /// No description provided for @ecomShopeeMaxDesc.
  ///
  /// In zh, this message translates to:
  /// **'Shopee 詳情圖最多張數'**
  String get ecomShopeeMaxDesc;

  /// No description provided for @ecomMomoMaxDesc.
  ///
  /// In zh, this message translates to:
  /// **'momo 詳情圖最多張數'**
  String get ecomMomoMaxDesc;

  /// No description provided for @ecomMomoMaxDescHelp.
  ///
  /// In zh, this message translates to:
  /// **'{min}–{max}（預設 18，保留空間給店家資訊圖）'**
  String ecomMomoMaxDescHelp(int min, int max);

  /// No description provided for @ecomShopeeMaxWidth.
  ///
  /// In zh, this message translates to:
  /// **'Shopee 最大寬度（px）'**
  String get ecomShopeeMaxWidth;

  /// No description provided for @ecomShopeeMaxWidthHelp.
  ///
  /// In zh, this message translates to:
  /// **'0 = 不限制；Shopee 前台約顯示到 1750'**
  String get ecomShopeeMaxWidthHelp;

  /// No description provided for @ecomShopeeMaxWidthError.
  ///
  /// In zh, this message translates to:
  /// **'需為 0 或 ≥ 750'**
  String get ecomShopeeMaxWidthError;

  /// No description provided for @ecomMomoMinLast.
  ///
  /// In zh, this message translates to:
  /// **'momo 詳情圖尾段最小高度（px）'**
  String get ecomMomoMinLast;

  /// No description provided for @ecomMomoMinLastHelp.
  ///
  /// In zh, this message translates to:
  /// **'低於此高度時從前一段挪高度；0 = 保持實際高度'**
  String get ecomMomoMinLastHelp;

  /// No description provided for @ecomMomoMinLastError.
  ///
  /// In zh, this message translates to:
  /// **'需小於 1500'**
  String get ecomMomoMinLastError;

  /// No description provided for @ecomQuality.
  ///
  /// In zh, this message translates to:
  /// **'品質'**
  String get ecomQuality;

  /// No description provided for @ecomQualityHelp.
  ///
  /// In zh, this message translates to:
  /// **'每張圖各自搜尋「符合大小限制的最高品質」，不超過下方上限'**
  String get ecomQualityHelp;

  /// No description provided for @ecomMaxQuality.
  ///
  /// In zh, this message translates to:
  /// **'品質上限'**
  String get ecomMaxQuality;

  /// No description provided for @ecomChroma444.
  ///
  /// In zh, this message translates to:
  /// **'色度 4:4:4'**
  String get ecomChroma444;

  /// No description provided for @ecomChroma444Help.
  ///
  /// In zh, this message translates to:
  /// **'文字與細線邊緣較清晰（尤其紅字），檔案較大'**
  String get ecomChroma444Help;

  /// No description provided for @ecomSmartCut.
  ///
  /// In zh, this message translates to:
  /// **'智慧切點'**
  String get ecomSmartCut;

  /// No description provided for @ecomSmartCutHelp.
  ///
  /// In zh, this message translates to:
  /// **'切段處往上 150px 內找最接近純色的橫列下刀，避免切到文字'**
  String get ecomSmartCutHelp;

  /// No description provided for @ecomDefaultFit.
  ///
  /// In zh, this message translates to:
  /// **'新加入圖片的預設處理'**
  String get ecomDefaultFit;

  /// No description provided for @ecomOverflowTitle.
  ///
  /// In zh, this message translates to:
  /// **'詳情圖張數超過上限'**
  String get ecomOverflowTitle;

  /// No description provided for @ecomOverflowLine.
  ///
  /// In zh, this message translates to:
  /// **'{platform}：會切成 {count} 張，上限 {limit} 張'**
  String ecomOverflowLine(String platform, int count, int limit);

  /// No description provided for @ecomOverflowHelp.
  ///
  /// In zh, this message translates to:
  /// **'整批未輸出任何檔案。請刪減詳情圖，或到設定調整上限後重試。'**
  String get ecomOverflowHelp;

  /// No description provided for @ecomResultTitle.
  ///
  /// In zh, this message translates to:
  /// **'已輸出 {count} 個檔案'**
  String ecomResultTitle(int count);

  /// No description provided for @ecomDisposed.
  ///
  /// In zh, this message translates to:
  /// **'已將 {count} 個舊檔移到垃圾桶'**
  String ecomDisposed(int count);

  /// No description provided for @ecomWarnCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 個檔案有警告'**
  String ecomWarnCount(int count);

  /// No description provided for @overwriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'將覆寫原檔'**
  String get overwriteTitle;

  /// No description provided for @overwriteBody.
  ///
  /// In zh, this message translates to:
  /// **'輸出位置與原檔相同且沒有後綴，原檔會先移到垃圾桶再寫入壓縮後的檔案。要繼續嗎？'**
  String get overwriteBody;

  /// No description provided for @normalDone.
  ///
  /// In zh, this message translates to:
  /// **'完成 {count}'**
  String normalDone(int count);

  /// No description provided for @normalKept.
  ///
  /// In zh, this message translates to:
  /// **'保留原檔 {count}'**
  String normalKept(int count);

  /// No description provided for @normalFailedCount.
  ///
  /// In zh, this message translates to:
  /// **'失敗 {count}'**
  String normalFailedCount(int count);

  /// No description provided for @listSep.
  ///
  /// In zh, this message translates to:
  /// **'，'**
  String get listSep;

  /// No description provided for @sizeChange.
  ///
  /// In zh, this message translates to:
  /// **'{before} → {after}（−{pct}%）'**
  String sizeChange(String before, String after, String pct);

  /// No description provided for @compressAll.
  ///
  /// In zh, this message translates to:
  /// **'全部壓縮'**
  String get compressAll;

  /// No description provided for @compressSelected.
  ///
  /// In zh, this message translates to:
  /// **'壓縮選取（{count}）'**
  String compressSelected(int count);

  /// No description provided for @clearAll.
  ///
  /// In zh, this message translates to:
  /// **'清空全部'**
  String get clearAll;

  /// No description provided for @removeSelected.
  ///
  /// In zh, this message translates to:
  /// **'移除選取（{count}）'**
  String removeSelected(int count);

  /// No description provided for @normalStatusIdle.
  ///
  /// In zh, this message translates to:
  /// **'{count} 張 · {size}'**
  String normalStatusIdle(int count, String size);

  /// No description provided for @normalStatusLast.
  ///
  /// In zh, this message translates to:
  /// **'上次：{change}'**
  String normalStatusLast(String change);

  /// No description provided for @colName.
  ///
  /// In zh, this message translates to:
  /// **'名稱'**
  String get colName;

  /// No description provided for @colOriginalSize.
  ///
  /// In zh, this message translates to:
  /// **'原大小'**
  String get colOriginalSize;

  /// No description provided for @colNewSize.
  ///
  /// In zh, this message translates to:
  /// **'新大小'**
  String get colNewSize;

  /// No description provided for @colResolution.
  ///
  /// In zh, this message translates to:
  /// **'解析度'**
  String get colResolution;

  /// No description provided for @colSaving.
  ///
  /// In zh, this message translates to:
  /// **'節省'**
  String get colSaving;

  /// No description provided for @colStatus.
  ///
  /// In zh, this message translates to:
  /// **'狀態'**
  String get colStatus;

  /// No description provided for @statusWorking.
  ///
  /// In zh, this message translates to:
  /// **'壓縮中…'**
  String get statusWorking;

  /// No description provided for @statusDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get statusDone;

  /// No description provided for @statusKept.
  ///
  /// In zh, this message translates to:
  /// **'保留原檔'**
  String get statusKept;

  /// No description provided for @statusFailed.
  ///
  /// In zh, this message translates to:
  /// **'失敗'**
  String get statusFailed;

  /// No description provided for @previewSelectHint.
  ///
  /// In zh, this message translates to:
  /// **'選取一張圖片以預覽'**
  String get previewSelectHint;

  /// No description provided for @previewOriginal.
  ///
  /// In zh, this message translates to:
  /// **'原圖'**
  String get previewOriginal;

  /// No description provided for @previewCompressed.
  ///
  /// In zh, this message translates to:
  /// **'壓縮後'**
  String get previewCompressed;

  /// No description provided for @previewEstimate.
  ///
  /// In zh, this message translates to:
  /// **'預估 {size}（{change}%）'**
  String previewEstimate(String size, String change);

  /// No description provided for @lossless.
  ///
  /// In zh, this message translates to:
  /// **'無損'**
  String get lossless;

  /// No description provided for @previewFailed.
  ///
  /// In zh, this message translates to:
  /// **'無法預覽：{error}'**
  String previewFailed(String error);

  /// No description provided for @tabCompression.
  ///
  /// In zh, this message translates to:
  /// **'壓縮'**
  String get tabCompression;

  /// No description provided for @tabOutput.
  ///
  /// In zh, this message translates to:
  /// **'輸出'**
  String get tabOutput;

  /// No description provided for @secMode.
  ///
  /// In zh, this message translates to:
  /// **'模式'**
  String get secMode;

  /// No description provided for @modeQuality.
  ///
  /// In zh, this message translates to:
  /// **'品質'**
  String get modeQuality;

  /// No description provided for @modeTargetSize.
  ///
  /// In zh, this message translates to:
  /// **'目標大小'**
  String get modeTargetSize;

  /// No description provided for @losslessHelp.
  ///
  /// In zh, this message translates to:
  /// **'JPEG 只重新最佳化編碼、PNG 用 oxipng、WebP 用無損模式'**
  String get losslessHelp;

  /// No description provided for @chromaSubsampling.
  ///
  /// In zh, this message translates to:
  /// **'色度取樣'**
  String get chromaSubsampling;

  /// No description provided for @chromaAuto.
  ///
  /// In zh, this message translates to:
  /// **'自動（品質 ≥ 90 用 4:4:4）'**
  String get chromaAuto;

  /// No description provided for @chroma444.
  ///
  /// In zh, this message translates to:
  /// **'4:4:4（最清晰）'**
  String get chroma444;

  /// No description provided for @chroma420.
  ///
  /// In zh, this message translates to:
  /// **'4:2:0（最小）'**
  String get chroma420;

  /// No description provided for @pngOptimize.
  ///
  /// In zh, this message translates to:
  /// **'最佳化'**
  String get pngOptimize;

  /// No description provided for @pngOptimizeHelp.
  ///
  /// In zh, this message translates to:
  /// **'等級越高越小但越慢；有損 PNG 以品質決定調色盤色數'**
  String get pngOptimizeHelp;

  /// No description provided for @secResize.
  ///
  /// In zh, this message translates to:
  /// **'縮放'**
  String get secResize;

  /// No description provided for @resizeMethod.
  ///
  /// In zh, this message translates to:
  /// **'縮放方式'**
  String get resizeMethod;

  /// No description provided for @resizeNone.
  ///
  /// In zh, this message translates to:
  /// **'不縮放'**
  String get resizeNone;

  /// No description provided for @resizePercentage.
  ///
  /// In zh, this message translates to:
  /// **'百分比'**
  String get resizePercentage;

  /// No description provided for @resizeWidth.
  ///
  /// In zh, this message translates to:
  /// **'固定寬度'**
  String get resizeWidth;

  /// No description provided for @resizeHeight.
  ///
  /// In zh, this message translates to:
  /// **'固定高度'**
  String get resizeHeight;

  /// No description provided for @resizeLongEdge.
  ///
  /// In zh, this message translates to:
  /// **'長邊'**
  String get resizeLongEdge;

  /// No description provided for @resizeShortEdge.
  ///
  /// In zh, this message translates to:
  /// **'短邊'**
  String get resizeShortEdge;

  /// No description provided for @resizeFitBox.
  ///
  /// In zh, this message translates to:
  /// **'縮放到框內（寬 × 高）'**
  String get resizeFitBox;

  /// No description provided for @valueWidth.
  ///
  /// In zh, this message translates to:
  /// **'寬度'**
  String get valueWidth;

  /// No description provided for @valueHeight.
  ///
  /// In zh, this message translates to:
  /// **'高度'**
  String get valueHeight;

  /// No description provided for @valueMaxWidth.
  ///
  /// In zh, this message translates to:
  /// **'寬度上限'**
  String get valueMaxWidth;

  /// No description provided for @valueMaxHeight.
  ///
  /// In zh, this message translates to:
  /// **'高度上限'**
  String get valueMaxHeight;

  /// No description provided for @noEnlarge.
  ///
  /// In zh, this message translates to:
  /// **'不放大'**
  String get noEnlarge;

  /// No description provided for @noEnlargeHelp.
  ///
  /// In zh, this message translates to:
  /// **'比目標小的圖片維持原尺寸'**
  String get noEnlargeHelp;

  /// No description provided for @resizeNote.
  ///
  /// In zh, this message translates to:
  /// **'一律等比縮放（Lanczos3）'**
  String get resizeNote;

  /// No description provided for @secFormat.
  ///
  /// In zh, this message translates to:
  /// **'格式'**
  String get secFormat;

  /// No description provided for @outputFormat.
  ///
  /// In zh, this message translates to:
  /// **'輸出格式'**
  String get outputFormat;

  /// No description provided for @formatSame.
  ///
  /// In zh, this message translates to:
  /// **'與原檔相同（BMP / TIFF / GIF 轉 PNG）'**
  String get formatSame;

  /// No description provided for @secLocation.
  ///
  /// In zh, this message translates to:
  /// **'位置'**
  String get secLocation;

  /// No description provided for @sameFolder.
  ///
  /// In zh, this message translates to:
  /// **'與原檔相同資料夾'**
  String get sameFolder;

  /// No description provided for @customFolder.
  ///
  /// In zh, this message translates to:
  /// **'指定資料夾'**
  String get customFolder;

  /// No description provided for @change.
  ///
  /// In zh, this message translates to:
  /// **'變更…'**
  String get change;

  /// No description provided for @keepStructure.
  ///
  /// In zh, this message translates to:
  /// **'保留資料夾結構'**
  String get keepStructure;

  /// No description provided for @keepStructureHelp.
  ///
  /// In zh, this message translates to:
  /// **'拖入資料夾時，依子資料夾分別輸出'**
  String get keepStructureHelp;

  /// No description provided for @secFileName.
  ///
  /// In zh, this message translates to:
  /// **'檔名'**
  String get secFileName;

  /// No description provided for @suffix.
  ///
  /// In zh, this message translates to:
  /// **'後綴'**
  String get suffix;

  /// No description provided for @overwriteWarning.
  ///
  /// In zh, this message translates to:
  /// **'同資料夾且無後綴：會覆寫原檔（原檔先移到垃圾桶）'**
  String get overwriteWarning;

  /// No description provided for @secMetadata.
  ///
  /// In zh, this message translates to:
  /// **'中繼資料'**
  String get secMetadata;

  /// No description provided for @keepMetadata.
  ///
  /// In zh, this message translates to:
  /// **'保留 EXIF 等中繼資料'**
  String get keepMetadata;

  /// No description provided for @keepMetadataHelp.
  ///
  /// In zh, this message translates to:
  /// **'ICC 色彩描述檔一律保留'**
  String get keepMetadataHelp;

  /// No description provided for @keepDates.
  ///
  /// In zh, this message translates to:
  /// **'保留檔案日期'**
  String get keepDates;

  /// No description provided for @secOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get secOther;

  /// No description provided for @skipIfBigger.
  ///
  /// In zh, this message translates to:
  /// **'壓縮後較大時保留原檔'**
  String get skipIfBigger;

  /// No description provided for @skipIfBiggerHelp.
  ///
  /// In zh, this message translates to:
  /// **'格式與尺寸不變時，改輸出原檔內容'**
  String get skipIfBiggerHelp;

  /// No description provided for @setLanguage.
  ///
  /// In zh, this message translates to:
  /// **'語言'**
  String get setLanguage;

  /// No description provided for @setTheme.
  ///
  /// In zh, this message translates to:
  /// **'主題'**
  String get setTheme;

  /// No description provided for @themeSystem.
  ///
  /// In zh, this message translates to:
  /// **'自動'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'淺色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @setColor.
  ///
  /// In zh, this message translates to:
  /// **'色彩'**
  String get setColor;

  /// No description provided for @colorFollowSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟隨系統色彩'**
  String get colorFollowSystem;

  /// No description provided for @colorFollowSystemHelp.
  ///
  /// In zh, this message translates to:
  /// **'Android 12 以上使用桌布色彩；Windows / macOS 使用系統強調色'**
  String get colorFollowSystemHelp;

  /// No description provided for @setFont.
  ///
  /// In zh, this message translates to:
  /// **'字體'**
  String get setFont;

  /// No description provided for @fontDefault.
  ///
  /// In zh, this message translates to:
  /// **'預設（系統字體）'**
  String get fontDefault;

  /// No description provided for @fontSample.
  ///
  /// In zh, this message translates to:
  /// **'圖片壓縮 Image Compressor 0123'**
  String get fontSample;

  /// No description provided for @setAbout.
  ///
  /// In zh, this message translates to:
  /// **'關於'**
  String get setAbout;

  /// No description provided for @aboutFontCredit.
  ///
  /// In zh, this message translates to:
  /// **'內建字體：MiSans、MiSans TC（小米 MiSans 字體，免費商用授權）'**
  String get aboutFontCredit;

  /// No description provided for @colonSep.
  ///
  /// In zh, this message translates to:
  /// **'：'**
  String get colonSep;

  /// No description provided for @heicUnsupportedShort.
  ///
  /// In zh, this message translates to:
  /// **'不支援 HEIC'**
  String get heicUnsupportedShort;

  /// No description provided for @errHeifWindows.
  ///
  /// In zh, this message translates to:
  /// **'此電腦無法讀取 HEIC：請從 Microsoft Store 安裝「HEIF 影像延伸模組」與「HEVC 視訊延伸模組」'**
  String get errHeifWindows;

  /// No description provided for @errHeifLinux.
  ///
  /// In zh, this message translates to:
  /// **'無法讀取 HEIC：請安裝 libheif1 與 libheif-plugin-libde265'**
  String get errHeifLinux;

  /// No description provided for @errHeifAndroid.
  ///
  /// In zh, this message translates to:
  /// **'此裝置無法讀取 HEIC（需要 Android 11 以上）'**
  String get errHeifAndroid;

  /// No description provided for @errHeifOther.
  ///
  /// In zh, this message translates to:
  /// **'此平台目前無法讀取 HEIC'**
  String get errHeifOther;

  /// No description provided for @aboutHeicOk.
  ///
  /// In zh, this message translates to:
  /// **'HEIC：可讀取（使用系統解碼器）'**
  String get aboutHeicOk;

  /// No description provided for @aboutHeicNo.
  ///
  /// In zh, this message translates to:
  /// **'HEIC：無法讀取'**
  String get aboutHeicNo;

  /// No description provided for @blockNoOutputFolder.
  ///
  /// In zh, this message translates to:
  /// **'請選擇輸出資料夾'**
  String get blockNoOutputFolder;

  /// No description provided for @blockNeedOutputFolder.
  ///
  /// In zh, this message translates to:
  /// **'有圖片不是從資料夾加入，請在「輸出」中指定資料夾'**
  String get blockNeedOutputFolder;

  /// No description provided for @chooseOutputFolder.
  ///
  /// In zh, this message translates to:
  /// **'選擇輸出資料夾'**
  String get chooseOutputFolder;

  /// No description provided for @outputTo.
  ///
  /// In zh, this message translates to:
  /// **'輸出到：{name}'**
  String outputTo(String name);

  /// No description provided for @sharedToWhich.
  ///
  /// In zh, this message translates to:
  /// **'把 {count} 張圖片加入哪一區？'**
  String sharedToWhich(int count);

  /// No description provided for @overwriteBodyAndroid.
  ///
  /// In zh, this message translates to:
  /// **'輸出位置與原檔相同且沒有後綴，原檔會先移到同資料夾的 _old 子資料夾，再寫入壓縮後的檔案。要繼續嗎？'**
  String get overwriteBodyAndroid;

  /// No description provided for @overwriteWarningAndroid.
  ///
  /// In zh, this message translates to:
  /// **'同資料夾且無後綴：會覆寫原檔（原檔先移到 _old 子資料夾）'**
  String get overwriteWarningAndroid;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
