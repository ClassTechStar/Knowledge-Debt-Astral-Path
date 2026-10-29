/**
 * 演示密钥 —— 对应 Web 版内嵌的演示密钥（源码里是密文块）。
 *
 * 鸿蒙侧不把密钥写进仓库：改成从资源 `app.string.demo_key` 读取，默认空串。
 * 要在本机演示时，把 entry/src/main/resources/base/element/string.json 里的
 * demo_key 填成你自己的 key 再打包（这份资源建议不要提交真实密钥）。
 * 用户自己在「账户」页填的 key 优先级更高。
 */
export class DemoKey {
  static value(): string {
    try {
      const ctx = getContext();
      const s = ctx.resourceManager.getStringSync($r('app.string.demo_key').id);
      return s === 'undefined' ? '' : (s ?? '');
    } catch (e) {
      return '';
    }
  }
}
