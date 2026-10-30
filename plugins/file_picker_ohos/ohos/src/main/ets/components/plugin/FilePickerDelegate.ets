/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import { EventSink } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import {
  common,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log, MethodResult } from '@ohos/flutter_ohos';
import { FileInfo } from './FileInfo'
import { FileUtils } from './FileUtils'
import List from '@ohos.util.List'
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const TAG: string = 'FilePickerDelegate';

export class FilePickerDelegate {
  private eventSink: EventSink | null = null;
  private pendingResult: MethodResult | null = null;
  private isMultipleSelection: boolean = false;
  private loadDataToMemory: boolean = false;
  private type: string = '';
  private allowedExtensions: string[] = [];
  private ability: UIAbility | null = null;
  private context: common.UIAbilityContext | null = null;
  private savaFilePath: string[] = [];
  private bytesList: Uint8Array[] = [];
  // 统计 withData 加载到 FileInfo 的文件数据累计大小，配合 100MB 上限避免二次读取路径绕过限制
  private totalLoadedBytes: number = 0;

  constructor(uiAbility: UIAbility) {
    this.ability = uiAbility;
  }

  async startFileExplorer(type: string, isMultipleSelection: boolean, withData: boolean,
    allowedExtensions: string[] | null | undefined,
    result: MethodResult) {
    if (!this.setPendingMethodCallAndResult(result)) {
      this.finishWithAlreadyActiveError(result);
      return;
    }
    this.type = type;
    this.isMultipleSelection = isMultipleSelection;
    this.loadDataToMemory = withData;
    this.bytesList = [];
    this.savaFilePath = [];
    if (allowedExtensions) {
      this.allowedExtensions = allowedExtensions;
    }
    // 通知 Dart 侧 onFileLoading 回调选取已开始；upstream 从未发送过该事件，
    // 只发送过 done，导致 picking 状态永远不会触发。此处补齐配对的开始事件。
    this.dispatchEventStatus(true);
    // await + 顶层异常保护，避免异步异常成为未处理的 Promise rejection
    try {
      await this.startFileExplorerA();
    } catch (error) {
      const e = error as BusinessError;
      console.error('startFileExplorerA failed with err: ' + JSON.stringify(error));
      this.finishWithError(e.code?.toString() ?? 'unknown', e.message ?? 'Unknown error');
    }
  }

  async startFileExplorerA() {
    const ability = this.ability;
    if (ability == null || ability.context == null) {
      this.finishWithError('no_activity', 'file picker requires a foreground ability');
      return;
    }
    let want: Want | null = null;
    switch (this.type) {
      case 'image': {
        let commonContext: common.UIAbilityContext = ability.context;
        let photoPicker = new picker.PhotoViewPicker(commonContext);
        let photoSelectOptions = new picker.PhotoSelectOptions();
        photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
        photoSelectOptions.maxSelectNumber = this.isMultipleSelection ? 9 : 1;
        try {
          const photoSelectResult = await photoPicker.select(photoSelectOptions);
          if (photoSelectResult == null || photoSelectResult.photoUris.length == 0) {
            await this.cancelOperation();
            return; // 取消后立即返回，避免继续处理空数组
          }
          this.savaFilePath = photoSelectResult.photoUris;
          // 文件数据由 openFileStream→loadData 加载到 FileInfo.bytes（含 100MB 上限），此处不再预读避免双重加载
          try {
            if (this.isMultipleSelection) {
              await this.handlingMultipleResults(photoSelectResult.photoUris)
            } else {
              await this.handleSingleResult(photoSelectResult.photoUris[0]);
            }
          } catch (error) {
            // 兜底捕获文件处理异常，避免 pendingResult 永不 resolve 导致 Flutter 端无限等待
            const err = error as BusinessError;
            this.finishWithError(err.code?.toString() ?? 'file_process_error',
              err.message ?? 'Failed to process selected files');
          }
        } catch (error) {
          const err = error as BusinessError;
          console.error('PhotoViewPicker.select failed with err: ' + JSON.stringify(error));
          this.finishWithError(err.code?.toString() ?? 'unknown', err.message ?? 'Unknown error');
        }
        break;
      }
      case 'video': {
        let commonContext: common.UIAbilityContext = ability.context;
        let photoPicker = new picker.PhotoViewPicker(commonContext);
        let photoSelectOptions = new picker.PhotoSelectOptions();
        photoSelectOptions.maxSelectNumber = this.isMultipleSelection ? 9 : 1;
        photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.VIDEO_TYPE;
        try {
          const photoSelectResult = await photoPicker.select(photoSelectOptions);
          if (photoSelectResult == null || photoSelectResult.photoUris.length == 0) {
            await this.cancelOperation();
            return; // 取消后立即返回，避免继续处理空数组
          }
          this.savaFilePath = photoSelectResult.photoUris;
          let selectedUris: string[] = photoSelectResult.photoUris;
          // 文件数据由 openFileStream→loadData 加载到 FileInfo.bytes（含 100MB 上限），此处不再预读避免双重加载
          try {
            if (this.isMultipleSelection) {
              await this.handlingMultipleResults(selectedUris)
            } else {
              await this.handleSingleResult(selectedUris[0]);
            }
          } catch (error) {
            // 兜底捕获文件处理异常，避免 pendingResult 永不 resolve 导致 Flutter 端无限等待
            const err = error as BusinessError;
            this.finishWithError(err.code?.toString() ?? 'file_process_error',
              err.message ?? 'Failed to process selected files');
          }
        } catch (error) {
          const err = error as BusinessError;
          console.error('PhotoViewPicker.select failed with err: ' + JSON.stringify(error));
          this.finishWithError(err.code?.toString() ?? 'unknown', err.message ?? 'Unknown error');
        }
        break;
      }
      case 'audio': {
        let context = getContext(this) as common.UIAbilityContext;
        let audioPicker: picker.AudioViewPicker = new picker.AudioViewPicker(context);
        let audioSelectOptions = new picker.AudioSelectOptions();
        audioSelectOptions.maxSelectNumber = this.isMultipleSelection ? 9 : 1;
        try {
          const audioSelectResult = await audioPicker.select(audioSelectOptions);
          if (audioSelectResult == null || audioSelectResult.length == 0) {
            await this.cancelOperation();
            return; // 取消后立即返回，避免继续处理空数组
          }
          this.savaFilePath = audioSelectResult;
          // 文件数据由 openFileStream→loadData 加载到 FileInfo.bytes（含 100MB 上限），此处不再预读避免双重加载
          try {
            if (this.isMultipleSelection) {
              await this.handlingMultipleResults(audioSelectResult);
            } else {
              await this.handleSingleResult(audioSelectResult[0]);
            }
          } catch (error) {
            // 兜底捕获文件处理异常，避免 pendingResult 永不 resolve 导致 Flutter 端无限等待
            const err = error as BusinessError;
            this.finishWithError(err.code?.toString() ?? 'file_process_error',
              err.message ?? 'Failed to process selected files');
          }
        } catch (error) {
          const err = error as BusinessError;
          console.error('AudioViewPicker.select failed with err: ' + JSON.stringify(error));
          this.finishWithError(err.code?.toString() ?? 'unknown', err.message ?? 'Unknown error');
        }
        break
      }
      case 'media': {
        let photoPicker = new photoAccessHelper.PhotoViewPicker();
        let photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
        photoSelectOptions.maxSelectNumber = this.isMultipleSelection ? 9 : 1;
        photoSelectOptions.MIMEType = this.resolveType(this.type) as photoAccessHelper.PhotoViewMIMETypes;
        try {
          const photoSelectResult = await photoPicker.select(photoSelectOptions);
          let selectedUris: string[] = photoSelectResult.photoUris;
          if (selectedUris == null || selectedUris.length == 0) {
            await this.cancelOperation();
            return; // 取消后立即返回，避免继续处理空数组
          }
          this.savaFilePath = selectedUris;
          // 文件数据由 openFileStream→loadData 加载到 FileInfo.bytes（含 100MB 上限），此处不再预读避免双重加载
          try {
            if (this.isMultipleSelection) {
              await this.handlingMultipleResults(selectedUris)
            } else {
              await this.handleSingleResult(selectedUris[0]);
            }
          } catch (error) {
            // 兜底捕获文件处理异常，避免 pendingResult 永不 resolve 导致 Flutter 端无限等待
            const err = error as BusinessError;
            this.finishWithError(err.code?.toString() ?? 'file_process_error',
              err.message ?? 'Failed to process selected files');
          }
        } catch (error) {
          const err = error as BusinessError;
          console.error('PhotoViewPicker.select failed with err: ' + JSON.stringify(error));
          this.finishWithError(err.code?.toString() ?? 'unknown', err.message ?? 'Unknown error');
        }
        break;
      }
      case 'any': {
        let commonContext: common.UIAbilityContext = ability.context;
        let documentPicker = new picker.DocumentViewPicker(commonContext);
        let documentSelectOptions = new picker.DocumentSelectOptions();
        documentSelectOptions.maxSelectNumber = this.isMultipleSelection ? 9 : 1;
        try {
          const documentSelectResult: string[] = await documentPicker.select(documentSelectOptions);
          if (documentSelectResult == null || documentSelectResult.length == 0) {
            await this.cancelOperation();
            return; // 取消后立即返回，避免继续处理空数组
          }
          this.savaFilePath = documentSelectResult;
          let anySelectUris: string[] = documentSelectResult;
          // 文件数据由 openFileStream→loadData 加载到 FileInfo.bytes（含 100MB 上限），此处不再预读避免双重加载
          try {
            if (this.isMultipleSelection) {
              await this.handlingMultipleResults(anySelectUris)
            } else {
              await this.handleSingleResult(anySelectUris[0]);
            }
          } catch (error) {
            // 兜底捕获文件处理异常，避免 pendingResult 永不 resolve 导致 Flutter 端无限等待
            const err = error as BusinessError;
            this.finishWithError(err.code?.toString() ?? 'file_process_error',
              err.message ?? 'Failed to process selected files');
          }
        } catch (error) {
          const err = error as BusinessError;
          console.error('DocumentViewPicker.select failed with err: ' + JSON.stringify(error));
          this.finishWithError(err.code?.toString() ?? 'unknown', err.message ?? 'Unknown error');
        }
        break
      }
      case 'custom': {
        let commonContext: common.UIAbilityContext = ability.context;
        let documentSelectOptions = new picker.DocumentSelectOptions();
        let documentPicker = new picker.DocumentViewPicker(commonContext);
        documentSelectOptions.maxSelectNumber = this.isMultipleSelection ? 9 : 1;
        documentSelectOptions.fileSuffixFilters = this.allowedExtensions;
        try {
          const documentSelectResult: string[] = await documentPicker.select(documentSelectOptions);
          if (documentSelectResult == null || documentSelectResult.length == 0) {
            await this.cancelOperation();
            return; // 取消后立即返回，避免继续处理空数组
          }
          this.savaFilePath = documentSelectResult;
          let anySelectUris: string[] = documentSelectResult;
          // 文件数据由 openFileStream→loadData 加载到 FileInfo.bytes（含 100MB 上限），此处不再预读避免双重加载
          try {
            if (this.isMultipleSelection) {
              await this.handlingMultipleResults(anySelectUris)
            } else {
              await this.handleSingleResult(anySelectUris[0]);
            }
          } catch (error) {
            // 兜底捕获文件处理异常，避免 pendingResult 永不 resolve 导致 Flutter 端无限等待
            const err = error as BusinessError;
            this.finishWithError(err.code?.toString() ?? 'file_process_error',
              err.message ?? 'Failed to process selected files');
          }
        } catch (error) {
          const err = error as BusinessError;
          console.error('DocumentViewPicker.select failed with err: ' + JSON.stringify(error));
          this.finishWithError(err.code?.toString() ?? 'unknown', err.message ?? 'Unknown error');
        }
        break
      }
      case 'dir': {
        let context = getContext(this) as common.UIAbilityContext;
        let documentPicker = new picker.DocumentViewPicker(context);
        let documentSelectOptions: picker.DocumentSelectOptions = {
          selectMode: 1
        }
        try {
          const documentSelectResult: string[] = await documentPicker.select(documentSelectOptions);
          if (documentSelectResult == null || documentSelectResult.length == 0) {
            await this.cancelOperation();
            return; // 取消后立即返回，避免继续处理空数组
          }
          let anySelectUris: string[] = documentSelectResult;
          // 文件数据由 openFileStream→loadData 加载到 FileInfo.bytes（含 100MB 上限），此处不再预读避免双重加载
          try {
            if (this.isMultipleSelection) {
              await this.handlingMultipleResults(anySelectUris)
            } else {
              await this.handleSingleResult(anySelectUris[0]);
            }
          } catch (error) {
            // 兜底捕获文件处理异常，避免 pendingResult 永不 resolve 导致 Flutter 端无限等待
            const err = error as BusinessError;
            this.finishWithError(err.code?.toString() ?? 'file_process_error',
              err.message ?? 'Failed to process selected files');
          }
        } catch (error) {
          const err = error as BusinessError;
          console.error('DocumentViewPicker.select failed with err: ' + JSON.stringify(error));
          this.finishWithError(err.code?.toString() ?? 'unknown', err.message ?? 'Unknown error');
        }
        break
      }
      default: {
        // 未知 type 直接以错误结束，避免 pendingResult 永不 resolve
        this.finishWithError('unknown_type', `Unsupported file type: ${this.type}`);
        break;
      }
    }
  }

  async handlingMultipleResults(uris: string[]) {
    let files: List<FileInfo> = new List();
    let count: number = uris.length;
    let currentItem = 0;
    this.totalLoadedBytes = 0;
    while (currentItem < count) {
      let currentUri: string = uris[currentItem];
      if (this.ability?.context) {
        let file: FileInfo | null =
          await FileUtils.openFileStream(this.ability?.context, currentUri, this.loadDataToMemory);
        if (file != null) {
          // 对二次读取路径（openFileStream→loadData）也施加累计大小限制，避免绕过 100MB 上限
          this.limitFileInfoData(file);
          files.add(file);
          this.cacheBytes(file);
          Log.d(TAG, '[MultiFilePick] File #' + currentItem + ' - URI: ' + currentUri);
        }
      }
      // 无论 ability 是否仍可用都递增，避免 dispose 后条件不成立导致死循环
      currentItem++;
    }
    this.finishWithSuccess(files);
  }

  async handleSingleResult(uris: string): Promise<void> {
    let files: List<FileInfo> = new List();
    this.totalLoadedBytes = 0;
    if (this.ability?.context) {
      let file: FileInfo | null =
        await FileUtils.openFileStream(this.ability?.context, uris, this.loadDataToMemory);
      if (file != null) {
        // 对二次读取路径（openFileStream→loadData）也施加累计大小限制，避免绕过 100MB 上限
        this.limitFileInfoData(file);
        files.add(file);
        this.cacheBytes(file);
      }
      if (!files.isEmpty()) {
        Log.d(TAG, 'File path:' + files.toString())
        this.finishWithSuccess(files);
      } else {
        this.finishWithError('unknown_path', 'Failed to retrieve path.');
      }
    } else {
      // ability 上下文不可用时以错误结束，避免 pendingResult 永不 resolve 导致 Flutter 端无限等待
      this.finishWithError('no_activity', 'Ability context is not available');
    }
  }

  /**
   * 对 FileInfo 携带的文件数据做累计大小限制：
   * withData=true 时 openFileStream→loadData 将文件数据读入 FileInfo.bytes，
   * 该路径是 pick 流程唯一的内存加载入口，累计不得超过 100MB。
   * 超出上限后丢弃后续文件的数据，仅保留路径/元数据，避免 OOM。
   */
  private limitFileInfoData(file: FileInfo): void {
    if (!this.loadDataToMemory) {
      return;
    }
    if (file.bytes != null && file.bytes.byteLength > 0) {
      this.totalLoadedBytes += file.bytes.byteLength;
      if (this.totalLoadedBytes > FilePickerDelegate.MAX_TOTAL_BYTES) {
        console.warn('Total in-memory file data exceeds 100MB limit, drop bytes of: ' + file.name);
        file.bytes = null;
      }
    }
  }

  /**
   * pick 时缓存文件数据到 bytesList，供后续 saveFile 使用：
   * save 调用只携带单份 bytes，多文件保存（multipleSave）需要每个文件各自的数据，
   * 该列表在原实现中由 pick 流程填充，是「先选取后保存」的数据来源。
   * 仅 withData=true（数据已加载到内存）时缓存，不产生额外文件读取；
   * 必须在 limitFileInfoData 之后调用，保证超限被丢弃的数据不会被缓存。
   */
  private cacheBytes(file: FileInfo): void {
    if (!this.loadDataToMemory) {
      return;
    }
    if (file.bytes != null && file.bytes.byteLength > 0) {
      this.bytesList.push(file.bytes);
    }
  }

  saveFinishWithSuccess(data: string) {
    this.dispatchEventStatus(false);
    this.pendingResult?.success(data);
    this.clearPendingResult();
    this.bytesList = [];
    this.savaFilePath = [];
  }

  finishWithSuccess(data: List<FileInfo>) {
    this.dispatchEventStatus(false);
    let result: List<Map<string, Object | null>> | null = null;
    if (this.pendingResult != null) {
      if (data != null) {
        let files: List<Map<string, Object | null>> = new List();
        data.forEach((file) => {
          files.add(file.toMap());
        })
        result = files
      }
    }
    this.pendingResult?.success(result);
    this.clearPendingResult();
    // 不清空 bytesList/savaFilePath：pick 的路径与数据是后续 saveFile（先选取后保存）
    // 推导源文件名/后缀的数据来源，保存完成（saveFinishWithSuccess）或发起新的 pick
    // （startFileExplorer）时才会重置
  }

  async saveFile(fileNameArray: string[], type: string | null, initialDirectory: string | null,
    allowedExtensions: string[], result: MethodResult, bytes: Uint8Array | null) {
    if (!this.setPendingMethodCallAndResult(result)) {
      this.finishWithAlreadyActiveError(result);
      return;
    }
    const ability = this.ability;
    if (ability == null || ability.context == null) {
      this.finishWithError('no_activity', 'file picker requires a foreground ability');
      return;
    }
    // 显式设置为非 'dir' 的操作类型，避免复用上一次 pick 遗留的 this.type === 'dir'
    // 导致 dispatchEventStatus 的保存事件被意外吞掉
    this.type = 'save';
    // 通知 Dart 侧 onFileSaving 回调保存已开始；upstream 从未发送过该事件，
    // 只发送过 done，导致 picking 状态永远不会触发。此处补齐配对的开始事件。
    this.dispatchEventStatus(true);
    // 优先使用本次调用传入的 bytes；兼容旧版「先选取后保存」流程
    // Modern file_picker saves the supplied bytes independently of earlier picks.
    if (bytes != null) {
      this.bytesList = [];
      this.savaFilePath = [];
    }
    const hasProvidedBytes: boolean = bytes != null;
    const saveBytes: Uint8Array | null = hasProvidedBytes ? bytes :
      (this.bytesList.length > 0 ? this.bytesList[0] : null);
    // 多文件保存（multipleSave）需要每个文件各自的数据，而 save 调用只携带单份 bytes，
    // 因此优先使用 pick 时缓存的 bytesList；未先选取时回退到传入的单份 bytes
    const saveDataList: Uint8Array[] = this.bytesList.length > 0 ? this.bytesList :
      (hasProvidedBytes ? [bytes as Uint8Array] : []);
    if (saveBytes == null) {
      this.finishWithError('', 'Bytes are required when saving a file');
      return;
    }

    let documentSaveOptions: picker.DocumentSaveOptions | null = null
    documentSaveOptions = new picker.DocumentSaveOptions();
    if (initialDirectory != null) {
      documentSaveOptions.defaultFilePathUri = initialDirectory;
    }
    if (allowedExtensions) {
      documentSaveOptions.fileSuffixChoices = allowedExtensions;
    }
    let commonContext: common.UIAbilityContext = ability.context;
    let documentPicker = new picker.DocumentViewPicker(commonContext);
    let sourceFileNameList: string[] = [];
    // 通过选择文件的路径，获取文件名
    for (const item of this.savaFilePath) {
      const lastSlashIndex = item.lastIndexOf('/');
      const sourceFileName = item.substring(lastSlashIndex + 1);
      sourceFileNameList.push(sourceFileName);
    }
    if (this.savaFilePath && this.savaFilePath.length > 1) {
      documentSaveOptions.newFileNames = sourceFileNameList;
    } else {
      // fileNameArray是 Default File Name 输入框的内容，如果为空，拉起文件选择器之后输入框有后缀（通过源文件获得）
      // documentSaveOptions.newFileNames是预设的文件名，拉起文件选择器自动显示在输入框中的
      const hasSourceFile: boolean = this.savaFilePath.length == 1;
      const sourceFileName: string = hasSourceFile ?
        this.savaFilePath[0].substring(this.savaFilePath[0].lastIndexOf('/') + 1) : '';
      const sourceExt: string = hasSourceFile ? getExtension(sourceFileName) : '';
      // 对实际文件名判断是否已带扩展名（修复原对空字符串判断恒为 false 的死代码）
      const hasExtension: boolean = hasFileExtension(fileNameArray[0]);
      let filePath: string = hasExtension ? fileNameArray[0] : fileNameArray[0] + sourceExt;
      documentSaveOptions.newFileNames = [filePath];
    }
    try {
      const documentSaveResult: string[] = await documentPicker.save(documentSaveOptions);
      if (documentSaveResult == null || documentSaveResult.length == 0) {
        await this.cancelOperation();
        return; // 取消后立即返回，避免继续访问空数组
      }
      let saveSuccess: boolean = false;
      if (documentSaveResult.length == 1) {
        // 如果在这个位置添加后缀，错误码: 13900002 错误信息: No such file or directory
        saveSuccess = this.singSave(documentSaveResult[0], saveBytes as Uint8Array);
      } else {
        //  选择多个文件后保存，只需要选择路径，不用添加文件名,重名自动加1
        saveSuccess = this.multipleSave(documentSaveResult, saveDataList);
      }
      if (!saveSuccess) {
        // 保存失败，错误已通过 finishWithError 上报，直接返回避免重复响应
        return;
      }
      let originFileName: string | null = FileUtils.getFileName(documentSaveResult[0])
      let newSavePath: string = documentSaveResult[0];
      if (originFileName != null) {
        let newFileName: string = FileUtils.urlDecodeManual(originFileName);
        newSavePath = FileUtils.replaceFileName(documentSaveResult[0], originFileName, newFileName);
      }
      this.saveFinishWithSuccess(newSavePath);
    } catch (error) {
      const err = error as BusinessError;
      const code: string = err.code?.toString() ?? 'save_failed';
      const message: string = err.message ?? 'Unknown save error';
      if (err.code == 13900001) {
        this.finishWithError(code, message + ', 此文件路径无权访问，只接受应用沙箱路径');
      } else {
        this.finishWithError(code, message);
      }
    }
  }
  // 内存上限：防止大文件/多文件选择导致 OOM（openFileStream→loadData 路径与 limitFileInfoData 共用）
  private static readonly MAX_TOTAL_BYTES: number = 100 * 1024 * 1024; // 100MB

  multipleSave(photoSaveResultUri: string[], dataArray: Uint8Array[]): boolean {
    let success: boolean = true;
    if (photoSaveResultUri.length > 1) {
      for (let i = 0; i < photoSaveResultUri.length; i++) {
        let targetFile: fs.File | null = null;
        try {
          targetFile =
            fs.openSync(photoSaveResultUri[i], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          fs.writeSync(targetFile.fd, dataArray[i]?.buffer);
          fs.fsyncSync(targetFile.fd); // 确保数据落盘
        } catch (error) {
          const e = error as BusinessError;
          console.error('multipleSave failed with err: ' + JSON.stringify(error));
          // 不抛异常，直接上报错误，避免二次异常导致 Flutter 端收不到响应
          this.finishWithError(e.code?.toString() ?? 'save_failed', `savefile 文件复制失败: ${e.message}`);
          success = false;
          break;
        } finally {
          if (targetFile !== null) {
            fs.closeSync(targetFile);
          }
        }
      }
    }
    return success;
  }

  singSave(photoSaveResultUri: string, data: Uint8Array): boolean {
    let targetFd: number | undefined;

    try {
      const targetFile: fs.File =
        fs.openSync(photoSaveResultUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      targetFd = targetFile.fd;
      fs.writeSync(targetFd, data.buffer);
      fs.fsyncSync(targetFd); // 确保数据落盘
      return true;
    } catch (error) {
      const e = error as BusinessError;
      console.error('singSave failed with err: ' + JSON.stringify(error));
      // 不抛异常，直接上报错误，避免 .catch 中 err.code 为 undefined 产生二次 TypeError
      this.finishWithError(e.code?.toString() ?? 'save_failed', `savefile 文件复制失败: ${e.message}`);
      return false;
    } finally {
      // 打开失败时 targetFd 可能为 undefined，避免 closeSync(undefined) 触发二次异常
      if (targetFd !== undefined) {
        fs.closeSync(targetFd);
      }
    }
  }

  private async cancelOperation(){
    // 与 dispatchEventStatus(true) 配对：取消也是一种结束，必须发出 done，
    // 否则 onFileLoading/onFileSaving 的监听方会永远停留在 picking 状态
    this.dispatchEventStatus(false);
    this.pendingResult?.success(null);
    this.clearPendingResult();
    // 不清空 bytesList/savaFilePath：取消本次选取/保存不应使之前成功选取的文件失效，
    // 后续 saveFile 仍可基于上一次成功 pick 的结果工作（与取消语义一致）
    return;
  }

  finishWithError(errorCode: string, errorMessage: string) {
    if (this.pendingResult == null) {
      return;
    }
    this.dispatchEventStatus(false);
    this.pendingResult.error(errorCode, errorMessage, null);
    this.clearPendingResult();
    // 不清空 bytesList/savaFilePath：失败后用户可能重试保存，保留上次 pick 的数据来源
  }

  dispatchEventStatus(status: boolean) {
    if (this.eventSink == null || this.type === 'dir') {
      return;
    }
    this.eventSink.success(status)
  }

  setEventHandler(eventSink: EventSink) {
    this.eventSink = eventSink;
  }

  removeEventHandler() {
    this.eventSink = null;
  }

  setPendingMethodCallAndResult(result: MethodResult): boolean {
    if (this.pendingResult != null) {
      return false;
    }
    this.pendingResult = result;
    return true;
  }

  finishWithAlreadyActiveError(result: MethodResult) {
    result.error('already_active', 'File picker is already active', null)
  }

  clearPendingResult() {
    this.pendingResult = null;
  }

  /**
   * 是否存在进行中的文件操作（pickFiles/saveFile 尚未结束）。
   * 供插件层 clear 等路径做并发守卫，避免与活跃操作并发执行导致数据竞争。
   */
  hasPendingResult(): boolean {
    return this.pendingResult != null;
  }

  resolveType(type: string) {
    switch (type) {
      case 'image':
        return photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      case 'video':
        return photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
      case 'media':
        return photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
      case 'any':
      default:
        return null;
    }
  }

  //
  clearBytesList():void {
   this.bytesList = [];
  }

  /**
   * 释放 delegate 持有的全部资源：
   * - resolve 正在进行的 pendingResult，避免 MethodResult 泄漏 / Flutter 端无限等待
   * - 解除事件订阅、清空文件数据与路径缓存、断开 Ability 引用
   */
  dispose(): void {
    // 有进行中的操作时先以错误结束（内部会清 pendingResult/bytesList/savaFilePath）
    this.finishWithError('plugin_detached', 'Plugin has been detached');
    this.eventSink = null;
    this.ability = null;
    this.context = null;
    // 无论是否有进行中的操作（pendingResult 为 null 时 finishWithError 提前返回），
    // 都显式清空全部内部状态，避免残留数据导致内存泄漏
    this.bytesList = [];
    this.savaFilePath = [];
    this.totalLoadedBytes = 0;
    this.allowedExtensions = [];
    this.type = '';
    this.isMultipleSelection = false;
    this.loadDataToMemory = false;
  }
}

/**
 * 获取文件扩展名
 */
function getExtension(fileName: string): string {
  const name = fileName.trim();
  const lastDotIndex = name.lastIndexOf('.');
  // 排除特殊情况
  if (lastDotIndex <= 0 ||
    lastDotIndex === name.length - 1 ||
  name.startsWith('.')) {
    return '';
  }
  // 返回包含点的扩展名（如 .txt、.jpg）
  return name.substring(lastDotIndex).toLowerCase();
}

/**
 * 判断路径是否包含扩展名
 * @param filePath 文件路径
 * @returns 是否包含扩展名
 */
function hasFileExtension(filePath: string): boolean {
  if (!filePath || filePath.trim() === '') {
    return false;
  }
  // 获取文件名（不包含路径）
  const fileName = filePath.substring(filePath.lastIndexOf('/') + 1);
  // 排除没有文件名的情况
  if (!fileName || fileName.trim() === '') {
    return false;
  }
  // 查找最后一个点号的位置
  const lastDotIndex = fileName.lastIndexOf('.');
  return lastDotIndex > 0 && lastDotIndex < fileName.length - 1;
}