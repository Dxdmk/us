const inArg = $arguments;
const FNAME = inArg.name == undefined ? "" : decodeURI(inArg.name);

if (typeof $surge !== "undefined") {
  $done({
    nodes: $surge.nodes.map(node => {
      node.name = FNAME + node.name;
      return node;
    })
  });
} else if (typeof $loon !== "undefined") {
  $done({
    nodeList: $loon.nodeList.map(node => {
      node.name = FNAME + node.name;
      return node;
    })
  });
} else {
  $done({});
}