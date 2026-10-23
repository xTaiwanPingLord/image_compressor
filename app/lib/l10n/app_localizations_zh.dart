// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '圖片壓縮';

  @override
  String get navNormal => '普通';

  @override
  String get navEcommerce => '電商';

  @override
  String get navSettings => '設定';

  @override
  String get close => '關閉';

  @override
  String get cancel => '取消';

  @override
  String get save => '儲存';

  @override
  String get continueAction => '繼續';

  @override
  String get gotIt => '知道了';

  @override
  String get resetDefaults => '還原預設';

  @override
  String get openFolder => '開啟資料夾';

  @override
  String get settingsTooltip => '設定';

  @override
  String get addImages => '加入圖片';

  @override
  String get addFolder => '加入資料夾';

  @override
  String get addFolderRecursive => '加入資料夾（含子資料夾）';

  @override
  String get remove => '移除';

  @override
  String get dropHere => '拖放圖片或資料夾到這裡';

  @override
  String get imagesTypeLabel => '圖片';

  @override
  String get pad => '補白';

  @override
  String get crop => '裁切';

  @override
  String get unreadable => '無法讀取';

  @override
  String get unknownError => '未知錯誤';

  @override
  String get runFailed => '執行失敗';

  @override
  String get blockRunning => '執行中';

  @override
  String get blockNoImages => '請先加入圖片';

  @override
  String get blockNoName => '請輸入 name';

  @override
  String get blockBadName => 'name 不能包含 \\ / : * ? \" < > |';

  @override
  String get blockNoPlatform => '請至少勾選一個平台';

  @override
  String get blockLoading => '讀取圖片資訊中';

  @override
  String get blockUnreadable => '有無法讀取的圖片，請先移除';

  @override
  String get errIo => '檔案存取錯誤';

  @override
  String get errDecode => '無法讀取圖片';

  @override
  String get errEncode => '編碼失敗';

  @override
  String get errInvalid => '設定錯誤';

  @override
  String get errTrash => '移到垃圾桶失敗';

  @override
  String get errOther => '錯誤';

  @override
  String warnOverMax(int quality, String size, String max) {
    return '品質降到 $quality 仍有 $size，超過上限 $max';
  }

  @override
  String warnDownscaled(int quality, int times, int width, int height) {
    return '品質降到 $quality 仍超標，解析度縮小 $times 次至 $width×$height';
  }

  @override
  String warnUnderMin(String size, String min) {
    return '檔案 $size 低於下限 $min（已用品質 100、4:4:4 並關閉最佳化）';
  }

  @override
  String get warnGifFirstFrame => 'GIF 只取第一格';

  @override
  String get warnJpegReencoded => 'JPEG 需重新編碼（縮放或轉檔），以品質 100、4:4:4 輸出';

  @override
  String warnTargetNotReached(String size, String target) {
    return '品質降到 1 仍有 $size，超過目標 $target';
  }

  @override
  String get ecomNameHint => '例如 223_ssd';

  @override
  String get ecomRun => '執行';

  @override
  String get ecomClearAll => '全部清空';

  @override
  String ecomEncoding(int done, int total) {
    return '壓縮中 $done / $total';
  }

  @override
  String get ecomWriting => '寫入檔案…';

  @override
  String get ecomPreparing => '讀取與排版…';

  @override
  String ecomStatus(
    int count,
    int shopee,
    int momo,
    String smart,
    String width,
    int quality,
  ) {
    return '共 $count 張 · 詳情圖上限 Shopee $shopee / momo $momo · 智慧切點$smart · Shopee 最大寬 $width · 品質上限 $quality';
  }

  @override
  String get on => '開';

  @override
  String get off => '關';

  @override
  String get unlimited => '不限';

  @override
  String get catMain => '主圖';

  @override
  String get catVariant => '選項圖';

  @override
  String get catDesc => '詳情圖';

  @override
  String imageCount(int count) {
    return '$count 張';
  }

  @override
  String get clearSection => '清空此區';

  @override
  String get enterNumber => '請輸入數字';

  @override
  String rangeHelp(int min, int max) {
    return '$min–$max';
  }

  @override
  String rangeError(int min, int max) {
    return '需在 $min–$max';
  }

  @override
  String get ecomSettingsTitle => '電商模式設定';

  @override
  String get ecomShopeeMaxDesc => 'Shopee 詳情圖最多張數';

  @override
  String get ecomMomoMaxDesc => 'momo 詳情圖最多張數';

  @override
  String ecomMomoMaxDescHelp(int min, int max) {
    return '$min–$max（預設 18，保留空間給店家資訊圖）';
  }

  @override
  String get ecomShopeeMaxWidth => 'Shopee 最大寬度（px）';

  @override
  String get ecomShopeeMaxWidthHelp => '0 = 不限制；Shopee 前台約顯示到 1750';

  @override
  String get ecomShopeeMaxWidthError => '需為 0 或 ≥ 750';

  @override
  String get ecomMomoMinLast => 'momo 詳情圖尾段最小高度（px）';

  @override
  String get ecomMomoMinLastHelp => '低於此高度時從前一段挪高度；0 = 保持實際高度';

  @override
  String get ecomMomoMinLastError => '需小於 1500';

  @override
  String get ecomQuality => '品質';

  @override
  String get ecomQualityHelp => '每張圖各自搜尋「符合大小限制的最高品質」，不超過下方上限';

  @override
  String get ecomMaxQuality => '品質上限';

  @override
  String get ecomChroma444 => '色度 4:4:4';

  @override
  String get ecomChroma444Help => '文字與細線邊緣較清晰（尤其紅字），檔案較大';

  @override
  String get ecomSmartCut => '智慧切點';

  @override
  String get ecomSmartCutHelp => '切段處往上 150px 內找最接近純色的橫列下刀，避免切到文字';

  @override
  String get ecomDefaultFit => '新加入圖片的預設處理';

  @override
  String get ecomOverflowTitle => '詳情圖張數超過上限';

  @override
  String ecomOverflowLine(String platform, int count, int limit) {
    return '$platform：會切成 $count 張，上限 $limit 張';
  }

  @override
  String get ecomOverflowHelp => '整批未輸出任何檔案。請刪減詳情圖，或到設定調整上限後重試。';

  @override
  String ecomResultTitle(int count) {
    return '已輸出 $count 個檔案';
  }

  @override
  String ecomDisposed(int count) {
    return '已將 $count 個舊檔移到垃圾桶';
  }

  @override
  String ecomWarnCount(int count) {
    return '$count 個檔案有警告';
  }

  @override
  String get overwriteTitle => '將覆寫原檔';

  @override
  String get overwriteBody => '輸出位置與原檔相同且沒有後綴，原檔會先移到垃圾桶再寫入壓縮後的檔案。要繼續嗎？';

  @override
  String normalDone(int count) {
    return '完成 $count';
  }

  @override
  String normalKept(int count) {
    return '保留原檔 $count';
  }

  @override
  String normalFailedCount(int count) {
    return '失敗 $count';
  }

  @override
  String get listSep => '，';

  @override
  String sizeChange(String before, String after, String pct) {
    return '$before → $after（−$pct%）';
  }

  @override
  String get compressAll => '全部壓縮';

  @override
  String compressSelected(int count) {
    return '壓縮選取（$count）';
  }

  @override
  String get clearAll => '清空全部';

  @override
  String removeSelected(int count) {
    return '移除選取（$count）';
  }

  @override
  String normalStatusIdle(int count, String size) {
    return '$count 張 · $size';
  }

  @override
  String normalStatusLast(String change) {
    return '上次：$change';
  }

  @override
  String get colName => '名稱';

  @override
  String get colOriginalSize => '原大小';

  @override
  String get colNewSize => '新大小';

  @override
  String get colResolution => '解析度';

  @override
  String get colSaving => '節省';

  @override
  String get colStatus => '狀態';

  @override
  String get statusWorking => '壓縮中…';

  @override
  String get statusDone => '完成';

  @override
  String get statusKept => '保留原檔';

  @override
  String get statusFailed => '失敗';

  @override
  String get previewSelectHint => '選取一張圖片以預覽';

  @override
  String get previewOriginal => '原圖';

  @override
  String get previewCompressed => '壓縮後';

  @override
  String previewEstimate(String size, String change) {
    return '預估 $size（$change%）';
  }

  @override
  String get lossless => '無損';

  @override
  String previewFailed(String error) {
    return '無法預覽：$error';
  }

  @override
  String get tabCompression => '壓縮';

  @override
  String get tabOutput => '輸出';

  @override
  String get secMode => '模式';

  @override
  String get modeQuality => '品質';

  @override
  String get modeTargetSize => '目標大小';

  @override
  String get losslessHelp => 'JPEG 只重新最佳化編碼、PNG 用 oxipng、WebP 用無損模式';

  @override
  String get chromaSubsampling => '色度取樣';

  @override
  String get chromaAuto => '自動（品質 ≥ 90 用 4:4:4）';

  @override
  String get chroma444 => '4:4:4（最清晰）';

  @override
  String get chroma420 => '4:2:0（最小）';

  @override
  String get pngOptimize => '最佳化';

  @override
  String get pngOptimizeHelp => '等級越高越小但越慢；有損 PNG 以品質決定調色盤色數';

  @override
  String get secResize => '縮放';

  @override
  String get resizeMethod => '縮放方式';

  @override
  String get resizeNone => '不縮放';

  @override
  String get resizePercentage => '百分比';

  @override
  String get resizeWidth => '固定寬度';

  @override
  String get resizeHeight => '固定高度';

  @override
  String get resizeLongEdge => '長邊';

  @override
  String get resizeShortEdge => '短邊';

  @override
  String get resizeFitBox => '縮放到框內（寬 × 高）';

  @override
  String get valueWidth => '寬度';

  @override
  String get valueHeight => '高度';

  @override
  String get valueMaxWidth => '寬度上限';

  @override
  String get valueMaxHeight => '高度上限';

  @override
  String get noEnlarge => '不放大';

  @override
  String get noEnlargeHelp => '比目標小的圖片維持原尺寸';

  @override
  String get resizeNote => '一律等比縮放（Lanczos3）';

  @override
  String get secFormat => '格式';

  @override
  String get outputFormat => '輸出格式';

  @override
  String get formatSame => '與原檔相同（BMP / TIFF / GIF 轉 PNG）';

  @override
  String get secLocation => '位置';

  @override
  String get sameFolder => '與原檔相同資料夾';

  @override
  String get customFolder => '指定資料夾';

  @override
  String get change => '變更…';

  @override
  String get keepStructure => '保留資料夾結構';

  @override
  String get keepStructureHelp => '拖入資料夾時，依子資料夾分別輸出';

  @override
  String get secFileName => '檔名';

  @override
  String get suffix => '後綴';

  @override
  String get overwriteWarning => '同資料夾且無後綴：會覆寫原檔（原檔先移到垃圾桶）';

  @override
  String get secMetadata => '中繼資料';

  @override
  String get keepMetadata => '保留 EXIF 等中繼資料';

  @override
  String get keepMetadataHelp => 'ICC 色彩描述檔一律保留';

  @override
  String get keepDates => '保留檔案日期';

  @override
  String get secOther => '其他';

  @override
  String get skipIfBigger => '壓縮後較大時保留原檔';

  @override
  String get skipIfBiggerHelp => '格式與尺寸不變時，改輸出原檔內容';

  @override
  String get setLanguage => '語言';

  @override
  String get setTheme => '主題';

  @override
  String get themeSystem => '自動';

  @override
  String get themeLight => '淺色';

  @override
  String get themeDark => '深色';

  @override
  String get setColor => '色彩';

  @override
  String get colorFollowSystem => '跟隨系統色彩';

  @override
  String get colorFollowSystemHelp =>
      'Android 12 以上使用桌布色彩；Windows / macOS 使用系統強調色';

  @override
  String get setFont => '字體';

  @override
  String get fontDefault => '預設（系統字體）';

  @override
  String get fontSample => '圖片壓縮 Image Compressor 0123';

  @override
  String get setAbout => '關於';

  @override
  String get aboutFontCredit => '內建字體：MiSans、MiSans TC（小米 MiSans 字體，免費商用授權）';

  @override
  String get colonSep => '：';
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn() : super('zh_CN');

  @override
  String get appTitle => '图片压缩';

  @override
  String get navNormal => '普通';

  @override
  String get navEcommerce => '电商';

  @override
  String get navSettings => '设置';

  @override
  String get close => '关闭';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get continueAction => '继续';

  @override
  String get gotIt => '知道了';

  @override
  String get resetDefaults => '恢复默认';

  @override
  String get openFolder => '打开文件夹';

  @override
  String get settingsTooltip => '设置';

  @override
  String get addImages => '添加图片';

  @override
  String get addFolder => '添加文件夹';

  @override
  String get addFolderRecursive => '添加文件夹（含子文件夹）';

  @override
  String get remove => '移除';

  @override
  String get dropHere => '拖放图片或文件夹到这里';

  @override
  String get imagesTypeLabel => '图片';

  @override
  String get pad => '补白';

  @override
  String get crop => '裁切';

  @override
  String get unreadable => '无法读取';

  @override
  String get unknownError => '未知错误';

  @override
  String get runFailed => '执行失败';

  @override
  String get blockRunning => '执行中';

  @override
  String get blockNoImages => '请先添加图片';

  @override
  String get blockNoName => '请输入 name';

  @override
  String get blockBadName => 'name 不能包含 \\ / : * ? \" < > |';

  @override
  String get blockNoPlatform => '请至少勾选一个平台';

  @override
  String get blockLoading => '读取图片信息中';

  @override
  String get blockUnreadable => '有无法读取的图片，请先移除';

  @override
  String get errIo => '文件访问错误';

  @override
  String get errDecode => '无法读取图片';

  @override
  String get errEncode => '编码失败';

  @override
  String get errInvalid => '设置错误';

  @override
  String get errTrash => '移到回收站失败';

  @override
  String get errOther => '错误';

  @override
  String warnOverMax(int quality, String size, String max) {
    return '质量降到 $quality 仍有 $size，超过上限 $max';
  }

  @override
  String warnDownscaled(int quality, int times, int width, int height) {
    return '质量降到 $quality 仍超标，分辨率缩小 $times 次至 $width×$height';
  }

  @override
  String warnUnderMin(String size, String min) {
    return '文件 $size 低于下限 $min（已用质量 100、4:4:4 并关闭优化）';
  }

  @override
  String get warnGifFirstFrame => 'GIF 只取第一帧';

  @override
  String get warnJpegReencoded => 'JPEG 需重新编码（缩放或转换），以质量 100、4:4:4 输出';

  @override
  String warnTargetNotReached(String size, String target) {
    return '质量降到 1 仍有 $size，超过目标 $target';
  }

  @override
  String get ecomNameHint => '例如 223_ssd';

  @override
  String get ecomRun => '执行';

  @override
  String get ecomClearAll => '全部清空';

  @override
  String ecomEncoding(int done, int total) {
    return '压缩中 $done / $total';
  }

  @override
  String get ecomWriting => '写入文件…';

  @override
  String get ecomPreparing => '读取与排版…';

  @override
  String ecomStatus(
    int count,
    int shopee,
    int momo,
    String smart,
    String width,
    int quality,
  ) {
    return '共 $count 张 · 详情图上限 Shopee $shopee / momo $momo · 智能切点$smart · Shopee 最大宽 $width · 质量上限 $quality';
  }

  @override
  String get on => '开';

  @override
  String get off => '关';

  @override
  String get unlimited => '不限';

  @override
  String get catMain => '主图';

  @override
  String get catVariant => '选项图';

  @override
  String get catDesc => '详情图';

  @override
  String imageCount(int count) {
    return '$count 张';
  }

  @override
  String get clearSection => '清空此区';

  @override
  String get enterNumber => '请输入数字';

  @override
  String rangeHelp(int min, int max) {
    return '$min–$max';
  }

  @override
  String rangeError(int min, int max) {
    return '需在 $min–$max';
  }

  @override
  String get ecomSettingsTitle => '电商模式设置';

  @override
  String get ecomShopeeMaxDesc => 'Shopee 详情图最多张数';

  @override
  String get ecomMomoMaxDesc => 'momo 详情图最多张数';

  @override
  String ecomMomoMaxDescHelp(int min, int max) {
    return '$min–$max（默认 18，保留空间给店铺信息图）';
  }

  @override
  String get ecomShopeeMaxWidth => 'Shopee 最大宽度（px）';

  @override
  String get ecomShopeeMaxWidthHelp => '0 = 不限制；Shopee 前台约显示到 1750';

  @override
  String get ecomShopeeMaxWidthError => '需为 0 或 ≥ 750';

  @override
  String get ecomMomoMinLast => 'momo 详情图尾段最小高度（px）';

  @override
  String get ecomMomoMinLastHelp => '低于此高度时从前一段挪高度；0 = 保持实际高度';

  @override
  String get ecomMomoMinLastError => '需小于 1500';

  @override
  String get ecomQuality => '质量';

  @override
  String get ecomQualityHelp => '每张图各自搜索“符合大小限制的最高质量”，不超过下方上限';

  @override
  String get ecomMaxQuality => '质量上限';

  @override
  String get ecomChroma444 => '色度 4:4:4';

  @override
  String get ecomChroma444Help => '文字与细线边缘更清晰（尤其红字），文件较大';

  @override
  String get ecomSmartCut => '智能切点';

  @override
  String get ecomSmartCutHelp => '切段处往上 150px 内找最接近纯色的横行下刀，避免切到文字';

  @override
  String get ecomDefaultFit => '新添加图片的默认处理';

  @override
  String get ecomOverflowTitle => '详情图张数超过上限';

  @override
  String ecomOverflowLine(String platform, int count, int limit) {
    return '$platform：会切成 $count 张，上限 $limit 张';
  }

  @override
  String get ecomOverflowHelp => '整批未输出任何文件。请删减详情图，或到设置调整上限后重试。';

  @override
  String ecomResultTitle(int count) {
    return '已输出 $count 个文件';
  }

  @override
  String ecomDisposed(int count) {
    return '已将 $count 个旧文件移到回收站';
  }

  @override
  String ecomWarnCount(int count) {
    return '$count 个文件有警告';
  }

  @override
  String get overwriteTitle => '将覆盖原文件';

  @override
  String get overwriteBody => '输出位置与原文件相同且没有后缀，原文件会先移到回收站再写入压缩后的文件。要继续吗？';

  @override
  String normalDone(int count) {
    return '完成 $count';
  }

  @override
  String normalKept(int count) {
    return '保留原文件 $count';
  }

  @override
  String normalFailedCount(int count) {
    return '失败 $count';
  }

  @override
  String get listSep => '，';

  @override
  String sizeChange(String before, String after, String pct) {
    return '$before → $after（−$pct%）';
  }

  @override
  String get compressAll => '全部压缩';

  @override
  String compressSelected(int count) {
    return '压缩选中（$count）';
  }

  @override
  String get clearAll => '清空全部';

  @override
  String removeSelected(int count) {
    return '移除选中（$count）';
  }

  @override
  String normalStatusIdle(int count, String size) {
    return '$count 张 · $size';
  }

  @override
  String normalStatusLast(String change) {
    return '上次：$change';
  }

  @override
  String get colName => '名称';

  @override
  String get colOriginalSize => '原大小';

  @override
  String get colNewSize => '新大小';

  @override
  String get colResolution => '分辨率';

  @override
  String get colSaving => '节省';

  @override
  String get colStatus => '状态';

  @override
  String get statusWorking => '压缩中…';

  @override
  String get statusDone => '完成';

  @override
  String get statusKept => '保留原文件';

  @override
  String get statusFailed => '失败';

  @override
  String get previewSelectHint => '选择一张图片以预览';

  @override
  String get previewOriginal => '原图';

  @override
  String get previewCompressed => '压缩后';

  @override
  String previewEstimate(String size, String change) {
    return '预计 $size（$change%）';
  }

  @override
  String get lossless => '无损';

  @override
  String previewFailed(String error) {
    return '无法预览：$error';
  }

  @override
  String get tabCompression => '压缩';

  @override
  String get tabOutput => '输出';

  @override
  String get secMode => '模式';

  @override
  String get modeQuality => '质量';

  @override
  String get modeTargetSize => '目标大小';

  @override
  String get losslessHelp => 'JPEG 只重新优化编码、PNG 用 oxipng、WebP 用无损模式';

  @override
  String get chromaSubsampling => '色度采样';

  @override
  String get chromaAuto => '自动（质量 ≥ 90 用 4:4:4）';

  @override
  String get chroma444 => '4:4:4（最清晰）';

  @override
  String get chroma420 => '4:2:0（最小）';

  @override
  String get pngOptimize => '优化';

  @override
  String get pngOptimizeHelp => '等级越高越小但越慢；有损 PNG 以质量决定调色板颜色数';

  @override
  String get secResize => '缩放';

  @override
  String get resizeMethod => '缩放方式';

  @override
  String get resizeNone => '不缩放';

  @override
  String get resizePercentage => '百分比';

  @override
  String get resizeWidth => '固定宽度';

  @override
  String get resizeHeight => '固定高度';

  @override
  String get resizeLongEdge => '长边';

  @override
  String get resizeShortEdge => '短边';

  @override
  String get resizeFitBox => '缩放到框内（宽 × 高）';

  @override
  String get valueWidth => '宽度';

  @override
  String get valueHeight => '高度';

  @override
  String get valueMaxWidth => '宽度上限';

  @override
  String get valueMaxHeight => '高度上限';

  @override
  String get noEnlarge => '不放大';

  @override
  String get noEnlargeHelp => '比目标小的图片保持原尺寸';

  @override
  String get resizeNote => '一律等比缩放（Lanczos3）';

  @override
  String get secFormat => '格式';

  @override
  String get outputFormat => '输出格式';

  @override
  String get formatSame => '与原文件相同（BMP / TIFF / GIF 转 PNG）';

  @override
  String get secLocation => '位置';

  @override
  String get sameFolder => '与原文件相同文件夹';

  @override
  String get customFolder => '指定文件夹';

  @override
  String get change => '更改…';

  @override
  String get keepStructure => '保留文件夹结构';

  @override
  String get keepStructureHelp => '拖入文件夹时，按子文件夹分别输出';

  @override
  String get secFileName => '文件名';

  @override
  String get suffix => '后缀';

  @override
  String get overwriteWarning => '同文件夹且无后缀：会覆盖原文件（原文件先移到回收站）';

  @override
  String get secMetadata => '元数据';

  @override
  String get keepMetadata => '保留 EXIF 等元数据';

  @override
  String get keepMetadataHelp => 'ICC 色彩配置文件始终保留';

  @override
  String get keepDates => '保留文件日期';

  @override
  String get secOther => '其他';

  @override
  String get skipIfBigger => '压缩后更大时保留原文件';

  @override
  String get skipIfBiggerHelp => '格式与尺寸不变时，改为输出原文件内容';

  @override
  String get setLanguage => '语言';

  @override
  String get setTheme => '主题';

  @override
  String get themeSystem => '自动';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get setColor => '颜色';

  @override
  String get colorFollowSystem => '跟随系统颜色';

  @override
  String get colorFollowSystemHelp =>
      'Android 12 及以上使用壁纸颜色；Windows / macOS 使用系统强调色';

  @override
  String get setFont => '字体';

  @override
  String get fontDefault => '默认（系统字体）';

  @override
  String get fontSample => '图片压缩 Image Compressor 0123';

  @override
  String get setAbout => '关于';

  @override
  String get aboutFontCredit => '内置字体：MiSans、MiSans TC（小米 MiSans 字体，免费商用授权）';

  @override
  String get colonSep => '：';
}
