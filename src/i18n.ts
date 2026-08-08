import type {Locale} from './types';

export const LOCALE_STORAGE_KEY = 'kalories.locale';

export interface Messages {
  appName: string;
  languageLabel: string;
  introEyebrow: string;
  introTitle: string;
  introBody: string;
  startCamera: string;
  cameraTitle: string;
  cameraHint: string;
  cameraReady: string;
  capture: string;
  analyzingEyebrow: string;
  analyzingTitle: string;
  analyzingBody: string;
  detectedFood: string;
  confidence: string;
  confidenceLow: string;
  confidenceMedium: string;
  confidenceHigh: string;
  assumptionsTitle: string;
  assumptionVisiblePortionOnly: string;
  assumptionPortionEstimated: string;
  assumptionSeasoningEstimated: string;
  assumptionHiddenIngredientsPossible: string;
  estimatedScore: string;
  strongestPositive: string;
  mainConcern: string;
  noClearPositive: string;
  noClearConcern: string;
  noMajorConcern: string;
  tierBalanced: string;
  tierMostlyBalanced: string;
  tierNeedsAttention: string;
  tierIndeterminate: string;
  calories: string;
  protein: string;
  carbs: string;
  fat: string;
  fiber: string;
  sugar: string;
  sodium: string;
  portion: string;
  statusLow: string;
  statusAppropriate: string;
  statusHigh: string;
  statusIndeterminate: string;
  sugarLow: string;
  adviceTitle: string;
  suggestionAddVegetables: string;
  suggestionReduceSauce: string;
  suggestionReduceSweetItems: string;
  suggestionReduceFat: string;
  suggestionAddProtein: string;
  suggestionAdjustStaple: string;
  suggestionReducePortion: string;
  saveResult: string;
  retake: string;
  retry: string;
  disclaimer: string;
  referenceBasis: string;
  errorCameraDenied: string;
  errorCaptureFailed: string;
  errorInvalidImage: string;
  errorUnsupportedImage: string;
  errorImageTooLarge: string;
  errorNoFood: string;
  errorServiceNotConfigured: string;
  errorRateLimited: string;
  errorAppCheckFailed: string;
  errorAppCheckUnavailable: string;
  errorAnalysisFailed: string;
  errorNetwork: string;
  errorSaveFailed: string;
}

export const messages: Record<Locale, Messages> = {
  zh: {
    appName: 'Kalories',
    languageLabel: '语言',
    introEyebrow: 'AI 饮食分析',
    introTitle: '一张照片，更了解这一餐。',
    introBody: '通过照片估算热量与营养结构。',
    startCamera: '打开相机',
    cameraTitle: '拍摄这一餐',
    cameraHint: '请让完整食物出现在取景框内',
    cameraReady: '已准备好分析',
    capture: '拍摄',
    analyzingEyebrow: '正在估算营养',
    analyzingTitle: '正在分析这一餐',
    analyzingBody: '正在识别份量与营养结构。',
    detectedFood: '识别到的食物',
    confidence: '估算可信度',
    confidenceLow: '低',
    confidenceMedium: '中',
    confidenceHigh: '高',
    assumptionsTitle: '估算前提',
    assumptionVisiblePortionOnly: '仅估算照片中可见的份量。',
    assumptionPortionEstimated: '份量根据外观估算。',
    assumptionSeasoningEstimated: '调味料用量为估算值。',
    assumptionHiddenIngredientsPossible: '可能含有照片中看不见的食材。',
    estimatedScore: '估算健康分',
    strongestPositive: '主要优点',
    mainConcern: '主要关注点',
    noClearPositive: '暂时无法判断明确优点。',
    noClearConcern: '信息不足，无法判断主要关注点。',
    noMajorConcern: '未发现明显需要关注的项目。',
    tierBalanced: '营养均衡',
    tierMostlyBalanced: '基本均衡',
    tierNeedsAttention: '需要关注',
    tierIndeterminate: '无法判断',
    calories: '热量',
    protein: '蛋白质',
    carbs: '碳水化合物',
    fat: '脂肪',
    fiber: '膳食纤维',
    sugar: '糖',
    sodium: '钠',
    portion: '估算份量',
    statusLow: '偏少',
    statusAppropriate: '适量',
    statusHigh: '偏多',
    statusIndeterminate: '无法估算',
    sugarLow: '较低',
    adviceTitle: '让它更均衡',
    suggestionAddVegetables: '可以增加一份蔬菜、豆类或海藻。',
    suggestionReduceSauce: '少放一些酱汁或汤汁，有助于减少钠。',
    suggestionReduceSweetItems: '可以减少甜饮、糖浆或甜味酱汁。',
    suggestionReduceFat: '可以减少油炸食物或高脂酱汁。',
    suggestionAddProtein: '可以增加鱼、蛋、豆腐或豆类。',
    suggestionAdjustStaple: '可以调整米饭、面包或面条等主食的份量。',
    suggestionReducePortion: '可以稍微减少总份量或高热量配料。',
    saveResult: '保存结果',
    retake: '重新拍摄',
    retry: '重新分析',
    disclaimer: '本结果为照片估算，仅作单餐参考，不是医疗诊断。',
    referenceBasis: '参考日本人饮食摄入标准（2025年版）及WHO指南。',
    errorCameraDenied: '无法使用相机，请检查浏览器权限。',
    errorCaptureFailed: '拍摄失败，请重试。',
    errorInvalidImage: '无法读取这张图片。',
    errorUnsupportedImage: '暂不支持这种图片格式。',
    errorImageTooLarge: '图片尺寸过大。',
    errorNoFood: '没有识别到食物，请重新拍摄完整餐食。',
    errorServiceNotConfigured: '分析服务尚未完成配置。',
    errorRateLimited: '请求过于频繁，请稍后再试。',
    errorAppCheckFailed: '无法验证此 App，请重新打开后再试。',
    errorAppCheckUnavailable: '暂时无法验证 App，请稍后再试。',
    errorAnalysisFailed: '分析失败，请稍后重试。',
    errorNetwork: '网络连接失败。',
    errorSaveFailed: '无法保存结果。',
  },
  ja: {
    appName: 'Kalories',
    languageLabel: '言語',
    introEyebrow: 'AI 食事分析',
    introTitle: '一枚の写真から、食事をもっと理解する。',
    introBody: 'カロリーと栄養バランスを写真から推定します。',
    startCamera: 'カメラを開く',
    cameraTitle: '食事を撮影',
    cameraHint: '料理全体が枠内に入るようにしてください',
    cameraReady: '分析の準備ができました',
    capture: '撮影する',
    analyzingEyebrow: '栄養を推定中',
    analyzingTitle: '食事を分析しています',
    analyzingBody: '量と栄養バランスを確認しています。',
    detectedFood: '推定した料理',
    confidence: '推定精度',
    confidenceLow: '低',
    confidenceMedium: '中',
    confidenceHigh: '高',
    assumptionsTitle: '推定の前提',
    assumptionVisiblePortionOnly: '写真に写っている量のみを推定しています。',
    assumptionPortionEstimated: '量は見た目から推定しています。',
    assumptionSeasoningEstimated: '調味料の量を推定しています。',
    assumptionHiddenIngredientsPossible:
      '写真に見えない材料が含まれる可能性があります。',
    estimatedScore: '推定スコア',
    strongestPositive: '主な良い点',
    mainConcern: '主な注目点',
    noClearPositive: 'はっきりした良い点を判断できません。',
    noClearConcern: '主な注目点を判断するには情報が足りません。',
    noMajorConcern: '大きな見直し点は見つかりませんでした。',
    tierBalanced: 'バランス良好',
    tierMostlyBalanced: 'おおむね良好',
    tierNeedsAttention: '見直しポイントあり',
    tierIndeterminate: '判定できません',
    calories: 'エネルギー',
    protein: 'たんぱく質',
    carbs: '炭水化物',
    fat: '脂質',
    fiber: '食物繊維',
    sugar: '糖類',
    sodium: 'ナトリウム',
    portion: '推定量',
    statusLow: '少なめ',
    statusAppropriate: '適量',
    statusHigh: '多め',
    statusIndeterminate: '推定不可',
    sugarLow: '低め',
    adviceTitle: 'より良くするには',
    suggestionAddVegetables: '野菜、豆類、海藻などを一品加えてみましょう。',
    suggestionReduceSauce: 'ソースや汁を少なめにすると塩分を抑えられます。',
    suggestionReduceSweetItems: '甘い飲み物やソースを控えめにしてみましょう。',
    suggestionReduceFat: '揚げ物や油の多いソースを少し減らしてみましょう。',
    suggestionAddProtein: '魚、卵、豆腐、豆類などを加えてみましょう。',
    suggestionAdjustStaple: 'ご飯、パン、麺など主食の量を調整してみましょう。',
    suggestionReducePortion: '量や高エネルギーなトッピングを少し減らしてみましょう。',
    saveResult: '結果を保存',
    retake: '撮り直す',
    retry: 'もう一度分析',
    disclaimer: '写真からの推定値です。1食の参考であり、医療上の診断ではありません。',
    referenceBasis: '日本人の食事摂取基準（2025年版）とWHO指針を参考にしています。',
    errorCameraDenied: 'カメラを利用できません。ブラウザの権限を確認してください。',
    errorCaptureFailed: '撮影できませんでした。もう一度お試しください。',
    errorInvalidImage: '画像を読み取れませんでした。',
    errorUnsupportedImage: 'この画像形式には対応していません。',
    errorImageTooLarge: '画像サイズが大きすぎます。',
    errorNoFood: '食事を認識できませんでした。料理全体を撮り直してください。',
    errorServiceNotConfigured: '分析サービスが設定されていません。',
    errorRateLimited: 'リクエストが多すぎます。少し待ってからお試しください。',
    errorAppCheckFailed: 'このアプリを確認できませんでした。アプリを開き直してお試しください。',
    errorAppCheckUnavailable: 'アプリを一時的に確認できません。しばらくしてからお試しください。',
    errorAnalysisFailed: '分析に失敗しました。しばらくしてからお試しください。',
    errorNetwork: 'ネットワークに接続できません。',
    errorSaveFailed: '結果を保存できませんでした。',
  },
  en: {
    appName: 'Kalories',
    languageLabel: 'Language',
    introEyebrow: 'AI meal analysis',
    introTitle: 'Understand your meal from one photo.',
    introBody: 'Estimate calories and nutritional balance from a photo.',
    startCamera: 'Open camera',
    cameraTitle: 'Photograph your meal',
    cameraHint: 'Keep the whole meal inside the frame',
    cameraReady: 'Ready to analyze',
    capture: 'Take photo',
    analyzingEyebrow: 'Estimating nutrition',
    analyzingTitle: 'Analyzing your meal',
    analyzingBody: 'Checking portion size and nutritional balance.',
    detectedFood: 'Estimated meal',
    confidence: 'Estimate confidence',
    confidenceLow: 'Low',
    confidenceMedium: 'Medium',
    confidenceHigh: 'High',
    assumptionsTitle: 'Estimation assumptions',
    assumptionVisiblePortionOnly: 'Only the visible portion is estimated.',
    assumptionPortionEstimated: 'Portion size is estimated visually.',
    assumptionSeasoningEstimated: 'Seasoning amounts are estimated.',
    assumptionHiddenIngredientsPossible:
      'Ingredients not visible in the photo may be present.',
    estimatedScore: 'Estimated score',
    strongestPositive: 'Strongest positive',
    mainConcern: 'Main concern',
    noClearPositive: 'Not enough information to identify a clear positive.',
    noClearConcern: 'Not enough information to identify a main concern.',
    noMajorConcern: 'No major concern was identified.',
    tierBalanced: 'Balanced',
    tierMostlyBalanced: 'Mostly balanced',
    tierNeedsAttention: 'Needs attention',
    tierIndeterminate: 'Unable to assess',
    calories: 'Calories',
    protein: 'Protein',
    carbs: 'Carbohydrates',
    fat: 'Fat',
    fiber: 'Dietary fibre',
    sugar: 'Sugars',
    sodium: 'Sodium',
    portion: 'Estimated portion',
    statusLow: 'Low',
    statusAppropriate: 'In range',
    statusHigh: 'High',
    statusIndeterminate: 'Unable to estimate',
    sugarLow: 'Lower',
    adviceTitle: 'Make it more balanced',
    suggestionAddVegetables: 'Consider adding vegetables, beans, or seaweed.',
    suggestionReduceSauce: 'Use less sauce or broth to reduce sodium.',
    suggestionReduceSweetItems: 'Reduce sweet drinks, syrups, or sweet sauces.',
    suggestionReduceFat: 'Reduce fried items or high-fat sauces.',
    suggestionAddProtein: 'Add fish, eggs, tofu, or beans.',
    suggestionAdjustStaple: 'Adjust the serving of rice, bread, or noodles.',
    suggestionReducePortion: 'Reduce the portion or energy-dense toppings slightly.',
    saveResult: 'Save result',
    retake: 'Retake',
    retry: 'Analyze again',
    disclaimer:
      'Values are estimated from a photo for single-meal reference only. This is not a medical diagnosis.',
    referenceBasis:
      'Based on the Dietary Reference Intakes for Japanese (2025) and WHO guidance.',
    errorCameraDenied: 'Camera access is unavailable. Check your browser permissions.',
    errorCaptureFailed: 'The photo could not be captured. Please try again.',
    errorInvalidImage: 'This image could not be read.',
    errorUnsupportedImage: 'This image format is not supported.',
    errorImageTooLarge: 'The image is too large.',
    errorNoFood: 'No meal was detected. Retake the photo with the whole meal visible.',
    errorServiceNotConfigured: 'The analysis service is not configured.',
    errorRateLimited: 'Too many requests. Try again shortly.',
    errorAppCheckFailed: 'This app could not be verified. Reopen it and try again.',
    errorAppCheckUnavailable: 'The app cannot be verified right now. Try again shortly.',
    errorAnalysisFailed: 'Analysis failed. Please try again shortly.',
    errorNetwork: 'The network connection failed.',
    errorSaveFailed: 'The result could not be saved.',
  },
};

const supportedLocales = new Set<Locale>(['zh', 'ja', 'en']);
const documentLanguages: Record<Locale, string> = {
  zh: 'zh-CN',
  ja: 'ja',
  en: 'en',
};

export function documentLanguage(locale: Locale): string {
  return documentLanguages[locale];
}

function supportedLocale(value: string | null | undefined): Locale | null {
  const baseLanguage = value?.trim().toLowerCase().split('-')[0];
  return baseLanguage && supportedLocales.has(baseLanguage as Locale)
    ? (baseLanguage as Locale)
    : null;
}

function savedLocale(): string | null {
  if (typeof window === 'undefined') {
    return null;
  }

  try {
    return window.localStorage.getItem(LOCALE_STORAGE_KEY);
  } catch {
    return null;
  }
}

function deviceLanguages(): readonly string[] {
  if (typeof navigator === 'undefined') {
    return [];
  }

  return navigator.languages.length > 0 ? navigator.languages : [navigator.language];
}

export function resolveLocale(
  saved: string | null = savedLocale(),
  preferredLanguages: readonly string[] = deviceLanguages(),
): Locale {
  const persisted = supportedLocale(saved);
  if (persisted) {
    return persisted;
  }

  for (const language of preferredLanguages) {
    const locale = supportedLocale(language);
    if (locale) {
      return locale;
    }
  }

  return 'ja';
}

export function persistLocale(locale: Locale): void {
  if (typeof window === 'undefined') {
    return;
  }

  try {
    window.localStorage.setItem(LOCALE_STORAGE_KEY, locale);
  } catch {
    // Locale persistence is a convenience and must not block the analysis flow.
  }
}
