/**
 * 更新日期：2024-04-05 15:30:15
 * 用法：Sub-Store 脚本操作添加
 * add-prefix.js
 */

// 获取输入参数
const inArg = $arguments; // console.log(inArg)
const PREFIX = inArg.prefix || "机场名"; // 默认前缀为 "机场名"

// 处理代理节点
function operator(proxies = [], targetPlatform, context) {
  proxies.forEach((proxy) => {
    // 在节点名前添加前缀，并保持原来的节点名在后方
    proxy.name = `${PREFIX} ${proxy.name}`;
  });

  return proxies;
}
