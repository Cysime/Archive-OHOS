import { common } from '@kit.AbilityKit';
import { ApiClient } from './api/ApiClient';
import { CloudflareManager } from './api/CloudflareManager';
import { PawchiveApi } from './api/PawchiveApi';
import { ArchiveDatabase } from './db/ArchiveDatabase';
import { ArchiveImageLoader } from './media/ArchiveImageLoader';
import { SecureStore } from './store/SecureStore';
import { SessionManager } from './store/SessionManager';
import { SettingsManager } from './store/SettingsManager';
import { Logger } from './util/Logger';
import { AuthRepository } from '../data/repo/AuthRepository';
import { BlockedContentRepository } from '../data/repo/BlockedContentRepository';
import { CreatorRepository } from '../data/repo/CreatorRepository';
import { FavoriteRepository } from '../data/repo/FavoriteRepository';
import { HistoryRepository } from '../data/repo/HistoryRepository';
import { PostRepository } from '../data/repo/PostRepository';
import { DownloadCenter } from '../data/download/DownloadCenter';
import { DownloadRuleRepository } from '../data/download/DownloadRuleRepository';
import { SearchHistoryRepository } from '../data/repo/SearchHistoryRepository';
import { AiCaller } from '../data/ai/AiCaller';
import { TranslationClient } from '../data/ai/TranslationClient';
import { TranslationSettingsRepository } from '../data/ai/TranslationSettingsRepository';
import { VisionClient } from '../data/ai/VisionClient';
import { OcrService } from '../data/ocr/OcrService';
import { BackupManager } from '../data/ops/BackupManager';
import { CacheRepository } from '../data/ops/CacheRepository';
import { SubscriptionRepository } from '../data/ops/SubscriptionRepository';
import { UpdateChecker } from '../data/ops/UpdateChecker';

const TAG: string = 'AppContainer';

/**
 * 全局应用依赖容器（替代 Android Hilt SingletonComponent）。
 * 在 EntryAbility.onCreate 完成异步初始化并预热屏蔽/收藏内存快照。
 */
export class AppContainer {
  private static instance?: AppContainer;

  readonly secureStore: SecureStore = new SecureStore();
  readonly settings: SettingsManager = new SettingsManager();
  readonly sessionManager: SessionManager;
  readonly cloudflare: CloudflareManager;
  readonly apiClient: ApiClient;
  readonly api: PawchiveApi;
  readonly database: ArchiveDatabase = new ArchiveDatabase();
  readonly imageLoader: ArchiveImageLoader;

  readonly blockedContent: BlockedContentRepository = new BlockedContentRepository();
  readonly creatorRepo: CreatorRepository;
  readonly historyRepo: HistoryRepository;
  readonly favoriteRepo: FavoriteRepository;
  readonly authRepo: AuthRepository;
  readonly postRepo: PostRepository;
  readonly downloadCenter: DownloadCenter;
  readonly downloadRules: DownloadRuleRepository;
  readonly searchHistory: SearchHistoryRepository;
  readonly aiSettings: TranslationSettingsRepository;
  readonly aiCaller: AiCaller = new AiCaller();
  readonly translationClient: TranslationClient;
  readonly visionClient: VisionClient;
  readonly ocrService: OcrService = new OcrService();
  readonly subscriptionRepo: SubscriptionRepository;
  readonly cacheRepo: CacheRepository;
  readonly backupManager: BackupManager;
  readonly updateChecker: UpdateChecker;

  private initialized: boolean = false;
  private appContext?: common.UIAbilityContext;

  private constructor() {
    this.sessionManager = new SessionManager(this.secureStore);
    this.cloudflare = new CloudflareManager(this.secureStore);
    this.apiClient = new ApiClient(this.settings, this.sessionManager, this.cloudflare);
    this.api = new PawchiveApi(this.apiClient);
    this.imageLoader = new ArchiveImageLoader(this.apiClient);

    this.creatorRepo = new CreatorRepository(this.api, this.database);
    this.historyRepo = new HistoryRepository(this.database, this.sessionManager);
    this.favoriteRepo = new FavoriteRepository(this.api, this.database, this.sessionManager, this.settings);
    this.authRepo = new AuthRepository(this.sessionManager, this.apiClient, this.favoriteRepo);
    this.postRepo = new PostRepository(this.api, this.favoriteRepo, this.creatorRepo);
    this.downloadCenter = new DownloadCenter(this.apiClient, this.database, this.settings, this.sessionManager);
    this.downloadRules = new DownloadRuleRepository(this.database);
    this.searchHistory = new SearchHistoryRepository(this.settings);
    this.aiSettings = new TranslationSettingsRepository(this.secureStore);
    this.translationClient = new TranslationClient(this.aiSettings, this.aiCaller);
    this.visionClient = new VisionClient(this.aiSettings, this.aiCaller);
    this.subscriptionRepo = new SubscriptionRepository(this.api, this.database);
    this.cacheRepo = new CacheRepository(
      this.apiClient,
      this.imageLoader,
      this.database,
      this.creatorRepo,
      this.favoriteRepo,
      this.historyRepo
    );
    this.backupManager = new BackupManager(
      this.settings,
      this.favoriteRepo,
      this.blockedContent,
      this.subscriptionRepo
    );
    this.updateChecker = new UpdateChecker(this.settings);
  }

  static getInstance(): AppContainer {
    if (AppContainer.instance === undefined) {
      AppContainer.instance = new AppContainer();
    }
    return AppContainer.instance;
  }

  getContext(): common.UIAbilityContext | undefined {
    return this.appContext;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.appContext = context;
    await this.secureStore.init(context);
    await this.settings.init(context);
    await this.sessionManager.init();
    await this.cloudflare.init();
    this.cloudflare.setTargetBaseUrl(this.settings.getSnapshot().baseUrl);
    await this.database.init(context);
    this.imageLoader.init(context);
    await this.blockedContent.init(context);
    await this.favoriteRepo.refreshLocalCache();
    await this.downloadCenter.init(context);
    await this.searchHistory.init(context);
    await this.aiSettings.init(context);
    this.cacheRepo.init(context);
    this.initialized = true;
    Logger.i(TAG, 'AppContainer initialization complete.');
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  destroy(): void {
    this.apiClient.close();
  }
}
