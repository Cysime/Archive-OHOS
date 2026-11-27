import { connection } from '@kit.NetworkKit';
import { Logger } from '../../core/util/Logger';

const TAG: string = 'NetworkStateHelper';

/**
 * 网络类型检测工具（用于「仅 Wi-Fi 下载」判断）。
 */
export class NetworkStateHelper {
  static async isWifiConnected(): Promise<boolean> {
    try {
      const netHandle = await connection.getDefaultNet();
      if (netHandle.netId === 0) {
        return false;
      }
      const caps = await connection.getNetCapabilities(netHandle);
      if (caps.bearerTypes !== undefined) {
        for (let i = 0; i < caps.bearerTypes.length; i++) {
          if (
            caps.bearerTypes[i] === connection.NetBearType.BEARER_WIFI ||
            caps.bearerTypes[i] === connection.NetBearType.BEARER_ETHERNET
          ) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      Logger.w(TAG, `isWifiConnected check failed: ${String(e)}`);
      return true;
    }
  }
}
