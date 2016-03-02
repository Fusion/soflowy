
var setting = {
  async: {
    enable: true,
    url:"/entries.json",
    autoParam:["id", "name=n", "level=lv"],
    otherParam:{"queryContext":0},
    dataFilter: filter
  },
  view: {expandSpeed:"",
    addHoverDom: addHoverDom,
    removeHoverDom: removeHoverDom,
                addDiyDom: addDiyDom,
    selectedMulti: false
  },
  edit: {
    enable: true,
                renameTitle: "Edit note",
                removeTitle: "Delete note"
  },
  data: {
    simpleData: {
      enable: true
    }
  },
  callback: {
    beforeRemove: beforeRemove,
    beforeRename: beforeRename,
    onRename: onRename,
    onRemove: onRemove
  }
};

var treeHistory = [];

function addLayer() {
console.log("+layer");
  var layer = '<div class="treelayer"><div class="zTreeContainerBackground left"><div id="backintree"><span class="icon icon-up-circled"></span></div><ul id="'+getTreeName()+'" class="ztree"></ul></div></div>';
  $('#content_wrap_container').append(layer);
}

function removeLayer() {
console.log("-layer");
  $("#" + getTreeName()).parent().parent().remove();
}

function treeup() {
  if(treeHistory.length > 0) {
    removeLayer();
    setting.async.otherParam.queryContext = treeHistory.pop();
  }
}

function getTreeName() {
  return "layertree_" + treeHistory.length;
}

function filter(treeId, parentNode, childNodes) {
  if (!childNodes) return null;
  for (var i=0, l=childNodes.length; i<l; i++) {
    childNodes[i].name = childNodes[i].name.replace(/\.n/g, '.');
  }
  return childNodes;
}

function beforeRemove(treeId, treeNode) {
  var zTree = $.fn.zTree.getZTreeObj(getTreeName());
  zTree.selectNode(treeNode);
  return confirm("Confirm delete node '" + treeNode.name + "' it?");
}

function onRemove(event, treeId, treeNode) {
  $.ajax({
    type: "POST",
    url: "/remove.json",
    data: { id: treeNode.id }
  });
}

function beforeRename(treeId, treeNode, newName) {
  if (newName.length == 0) {
    alert("Node name can not be empty.");
    return false;
  }
  return true;
}

function onRename(event, treeId, treeNode, isCancel) {
  if(!isCancel) {
    $.ajax({
      type: "POST",
      url: "/rename.json",
      data: { id: treeNode.id, content: treeNode.name },

      success: function( data ) {
        addDiyDom(treeId, treeNode);
      }
    });
  }
  else {
    addDiyDom(treeId, treeNode);
  }
}

function addRemoteNode(treeNode) {
  name = "";

  $.ajax({
    type: "POST",
    url: "/add.json",
    data: { pid: treeNode.id, content: name },

    success: function( data ) {
      var zTree = $.fn.zTree.getZTreeObj(getTreeName());
      zTree.addNodes(treeNode, {id:data.id, pId:treeNode.id, name:name});
      newCount++;
      var node = zTree.getNodeByParam("id", data.id, treeNode);
      zTree.selectNode(node);
      zTree.editName(node);
    }
  });
}

function checkTask(treeNode, ischecked) {
  $.ajax({
    type: "POST",
    url: "/checktask.json",
    data: { id: treeNode.id, checked: ischecked ? "true" : "false" },
  });
}

function makeTask(treeNode, istask) {
  $.ajax({
    type: "POST",
    url: "/maketask.json",
    data: { id: treeNode.id, task: istask ? "false" : "true" },

    success: function( data ) {
      treeNode.task = !istask;
      var zTree = $.fn.zTree.getZTreeObj(getTreeName());
      var node = zTree.getNodeByParam("id", data.id, treeNode);
      addDiyDom(zTree.setting.treeId, treeNode);
    }
  });
}

/* DEAD CODE */
function onClick(event, treeId, treeNode, clickFlag) {
  treeHistory.push(setting.async.otherParam.queryContext);
  addLayer();

  setting.async.otherParam.queryContext = treeNode.id;
  $.fn.zTree.init($("#"+getTreeName()), setting);
}

var newCount = 1;
function addHoverDom(treeId, treeNode) {
  var sObj = $("#" + treeNode.tId + "_span");
  if (treeNode.editNameFlag || $("#addBtn_"+treeNode.tId).length>0) return;
  var addStr = "<span class='button add' id='addBtn_" + treeNode.tId
    + "' title='add child note' onfocus='this.blur();'></span>"
          + "<span class='button task' id='taskBtn_" + treeNode.tId
    + "' title='make task' onfocus='this.blur();'></span>"
  sObj.after(addStr);
  var btn = $("#addBtn_"+treeNode.tId);
  if (btn) btn.bind("click", function(){
    addRemoteNode(treeNode);
    return false;
  });
  var btn2 = $("#taskBtn_"+treeNode.tId);
  if (btn2) btn2.bind("click", function(){
                makeTask(treeNode, treeNode.task);
    return false;
  });
};

function removeHoverDom(treeId, treeNode) {
  $("#taskBtn_"+treeNode.tId).unbind().remove();
  $("#addBtn_"+treeNode.tId).unbind().remove();
};

function addDiyDom(treeId, treeNode) {
  if(typeof treeId == "undefined") return;
  var sObj = $("#" + treeNode.tId + "_span");
  sObj.html(renderContent(sObj.html()));

  if(sObj.parent().find("#dig_"+treeNode.id).length < 1) {
    var digStr = "<span class='digBtn' id='dig_" +treeNode.id+ "' onfocus='this.blur();'> </span>";
    sObj.before(digStr);
    var digBtn = $("#dig_"+treeNode.id);
    if (digBtn) digBtn.unbind("click").click(function(e) {
      treeHistory.push(setting.async.otherParam.queryContext);
      addLayer();

      setting.async.otherParam.queryContext = treeNode.id;
      $.fn.zTree.init($("#"+getTreeName()), setting);
    });
  }

  if(treeNode.task) {
    if(sObj.parent().find("#checkbox_"+treeNode.id).length < 1) {
      var checkStr = "<input type='checkbox' class='checkboxBtn' id='checkbox_" +treeNode.id+ "'" + ( treeNode.checked ? "checked=checked" : "" ) + " onfocus='this.blur();'></input>";
      sObj.before(checkStr);
      var checkBtn = $("#checkbox_"+treeNode.id);
      if (checkBtn) checkBtn.unbind("click").bind("change", function(e) {
        checkTask(treeNode, e.currentTarget.checked);
        return false;
      });
    }
  }
  else {
    $("#checkbox_"+treeNode.id).unbind().remove();
  }

}

/* */

function renderContent(str) {
  //return marked(str).replace(/(\+[a-zA-z-_0-9]*)/g, '<span class="tag" style="background-color:#82caff">$1</span>');
  return str.replace(/(\+[a-zA-z-_0-9]*)/g, '<span class="tag" style="background-color:#82caff">$1</span>');
}

/* */

function onKeyEnter() {
  var zTree = $.fn.zTree.getZTreeObj(getTreeName());
  var snodes = zTree.getSelectedNodes();
  if(snodes.length > 0) {
    // A node is selected:
    // We are going to edit it
    zTree.editName(snodes[0]);
  }
  else {
    // No node selected:
    // We should select one
    var nodes = zTree.getNodes();
    if(nodes.length > 0) {
      zTree.selectNode(nodes[0]);
    }
    else {
      // No nodes to select (yet)
      // TODO add first node if empty tree
    }
  }
}

function onKeyEsc() {
  treeup();
}

function onKeyDel() {
  var zTree = $.fn.zTree.getZTreeObj(getTreeName());
  var snodes = zTree.getSelectedNodes();
  if(snodes.length > 0) {
    zTree.removeNode(snodes[0], true);
  }
}

function onKeySpace() {
  var zTree = $.fn.zTree.getZTreeObj(getTreeName());
  var snodes = zTree.getSelectedNodes();
  if(snodes.length > 0) {
    $("#checkbox_"+snodes[0].id).click().change();
  }
}

function onKeyShiftSpace() {
  var zTree = $.fn.zTree.getZTreeObj(getTreeName());
  var snodes = zTree.getSelectedNodes();
  if(snodes.length > 0) {
    $("#dig_"+snodes[0].id).click();
  }
}

function findNextFirstParent(node) {
  if(node.getNextNode()) {
    return node.getNextNode();
  }
  if(node.getParentNode()) {
    return findNextFirstParent(node.getParentNode());
  }
  else {
    return null;
  }
}

function onKeyDown() {
  var zTree = $.fn.zTree.getZTreeObj(getTreeName());
  var nodes = zTree.getSelectedNodes();
  if(nodes.length > 0) {
    if(nodes[0].isParent && nodes[0].open == true) {
      zTree.selectNode(nodes[0].children[0]);
    }
    else {
      if(nodes[0].getNextNode()) {
        zTree.selectNode(nodes[0].getNextNode());
      }
      else if(nodes[0].getParentNode()) {
        nextNode = findNextFirstParent(nodes[0].getParentNode());
        if(nextNode != null) {
          zTree.selectNode(nextNode);
        }
      }
    }
  }
  else {
    onKeyEnter();
  }
}

/* This is where is get fun:
 * we want to recursively find the
 * last grandchild from our predecessor's lineage
 */
function findPreviousLastChild(node) {
  if(node.isParent == false) {
    return node;
  }
  if(node.open == false) {
    return node;
  }
  return findPreviousLastChild(node.children[node.children.length - 1]);
}

function onKeyUp() {
  var zTree = $.fn.zTree.getZTreeObj(getTreeName());
  var nodes = zTree.getSelectedNodes();
  if(nodes.length > 0) {
    if(nodes[0].getPreNode()) {
      zTree.selectNode(findPreviousLastChild(nodes[0].getPreNode()));
    }
    else if(nodes[0].getParentNode()) {
      zTree.selectNode(nodes[0].getParentNode());
    }
  }
}

function onKeyRight() {
  var zTree = $.fn.zTree.getZTreeObj(getTreeName());
  var nodes = zTree.getSelectedNodes();
  if(nodes.length > 0) {
    if(nodes[0].isParent && nodes[0].open == false) {
      zTree.expandNode(nodes[0], true);
    }
  }
}

function onKeyLeft() {
  var zTree = $.fn.zTree.getZTreeObj(getTreeName());
  var nodes = zTree.getSelectedNodes();
  if(nodes.length > 0) {
    if(nodes[0].isParent && nodes[0].open == true) {
      zTree.expandNode(nodes[0], false);
    }
  }
}

function onKeyShiftEnter() {
  var zTree = $.fn.zTree.getZTreeObj(getTreeName());
  var nodes = zTree.getSelectedNodes();
  if(nodes.length > 0) {
    if(nodes[0].getParentNode()) {
      addRemoteNode(nodes[0].getParentNode());
    }
    else {
      addRemoteNode(0);
    }
  }
}

$(document).ready(function(){

        addLayer();

  /*
   * Key combos: by default, no node is selected... Enter will be used to either
   * select the top node or create a new node
   */
  var bindings = new Keys.Bindings();
  bindings.add('onKeyEnter', new Keys.Combo(Keys.Key.Enter));
  bindings.registerHandler(onKeyEnter);
  bindings.add('onKeyEsc', new Keys.Combo(Keys.Key.Esc));
  bindings.registerHandler(onKeyEsc);
  bindings.add('onKeyDel', new Keys.Combo(Keys.Key.Delete));
  bindings.registerHandler(onKeyDel);
  bindings.add('onKeyDown', new Keys.Combo(Keys.Key.Down));
  bindings.registerHandler(onKeyDown);
  bindings.add('onKeyUp', new Keys.Combo(Keys.Key.Up));
  bindings.registerHandler(onKeyUp);
  bindings.add('onKeyRight', new Keys.Combo(Keys.Key.Right));
  bindings.registerHandler(onKeyRight);
  bindings.add('onKeyLeft', new Keys.Combo(Keys.Key.Left));
  bindings.registerHandler(onKeyLeft);
  bindings.add('onKeyShiftEnter', new Keys.Combo(Keys.Key.Enter, Keys.Key.SHIFT));
  bindings.registerHandler(onKeyShiftEnter);
  bindings.add('onKeySpace', new Keys.Combo(Keys.Key.Spacebar));
  bindings.registerHandler(onKeySpace);
  bindings.add('onKeyShiftSpace', new Keys.Combo(Keys.Key.Spacebar, Keys.Key.SHIFT));
  bindings.registerHandler(onKeyShiftSpace);

  $.fn.zTree.init($("#"+getTreeName()), setting);
        /*
         * If back arrow clicked, then pop tree history
         */
  $("#backintree").click(function() {
          treeup();
  });
});
