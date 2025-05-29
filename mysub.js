function operator(proxies = [], targetPlatform, context) {
  // 获取参数中的机场名前缀
  const prefix = context.args.prefix || "机场名"; // 默认前缀为 "机场名"

  // 遍历每个节点并添加前缀
  proxies.forEach(proxy => {
    proxy.name = `${prefix} ${proxy.name}`; // 在节点名前添加前缀
  });

  // 返回处理后的代理节点数组
  return proxies;
}

// 示例调用
// const result = operator([{ name: "节点1" }, { name: "节点2" }], "目标平台", { args: { prefix: "MM" } });
// console.log(result);
