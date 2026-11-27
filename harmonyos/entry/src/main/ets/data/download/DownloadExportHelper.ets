import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { Logger } from '../../core/util/Logger';

const TAG: string = 'DownloadExportHelper';

/**
 * 使用 HarmonyOS `DocumentViewPicker` 将已下载文件导出到用户指定系统目录（替代 Android SAF）。
 */
export class DownloadExportHelper {
  static async exportFileWithPicker(
    context: common.UIAbilityContext,
    sourcePath: string,
    suggestedFileName: string
  ): Promise<string | undefined> {
    try {
      if (!fileIo.accessSync(sourcePath)) {
        return undefined;
      }
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [suggestedFileName];
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris = await documentPicker.save(saveOptions);
      if (uris.length === 0) {
        return undefined;
      }
      const targetUri = uris[0];
      const srcFile = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
      const dstFile = fileIo.openSync(targetUri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        const chunk = new ArrayBuffer(65536);
        let bytesRead = fileIo.readSync(srcFile.fd, chunk);
        while (bytesRead > 0) {
          fileIo.writeSync(dstFile.fd, chunk, { length: bytesRead });
          bytesRead = fileIo.readSync(srcFile.fd, chunk);
        }
      } finally {
        fileIo.closeSync(srcFile.fd);
        fileIo.closeSync(dstFile.fd);
      }
      return targetUri;
    } catch (e) {
      Logger.w(TAG, `exportFileWithPicker failed: ${String(e)}`);
      return undefined;
    }
  }
}
