
var setting = {
	async: {
		enable: true,
		url:"/entries.json",
		autoParam:["id", "name=n", "level=lv"],
		otherParam:{"queryParent":0},
		dataFilter: filter
	},
	view: {expandSpeed:"",
		addHoverDom: addHoverDom,
		removeHoverDom: removeHoverDom,
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
		onRemove: onRemove,
		onClick: onClick
	}
};

function filter(treeId, parentNode, childNodes) {
	if (!childNodes) return null;
	for (var i=0, l=childNodes.length; i<l; i++) {
		childNodes[i].name = childNodes[i].name.replace(/\.n/g, '.');
	}
	return childNodes;
}

function beforeRemove(treeId, treeNode) {
	var zTree = $.fn.zTree.getZTreeObj("treeDemo");
	zTree.selectNode(treeNode);
	return confirm("Confirm delete node '" + treeNode.name + "' it?");
}

function onRemove(event, treeId, treeNode) {
  $.ajax({
    method: "POST",
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
      method: "POST",
      url: "/rename.json",
      data: { id: treeNode.id, content: treeNode.name }
    });
  }
}

function addRemoteNode(treeNode) {
    name = "";

    $.ajax({
      method: "POST",
      url: "/add.json",
      data: { pid: treeNode.id, content: name },

      success: function( data ) {
        var zTree = $.fn.zTree.getZTreeObj("treeDemo");
        zTree.addNodes(treeNode, {id:data.id, pId:treeNode.id, name:name});
        newCount++;
        var node = zTree.getNodeByParam("id", data.id, treeNode);
        zTree.selectNode(node);
        zTree.editName(node);
      }
    });
}

function onClick(event, treeId, treeNode, clickFlag) {
	//console.log("[ "+getTime()+" onClick ]&nbsp;&nbsp;clickFlag = " + clickFlag + " (" + (clickFlag===1 ? "single selected": (clickFlag===0 ? "<b>cancel selected</b>" : "<b>multi selected</b>")) + ")");
        treeHistory.push(setting.async.otherParam.queryParent);
	setting.async.otherParam.queryParent = treeNode.id;
	$.fn.zTree.init($("#treeDemo"), setting);
}

var newCount = 1;
function addHoverDom(treeId, treeNode) {
	var sObj = $("#" + treeNode.tId + "_span");
	if (treeNode.editNameFlag || $("#addBtn_"+treeNode.tId).length>0) return;
	var addStr = "<span class='button add' id='addBtn_" + treeNode.tId
		+ "' title='add child note' onfocus='this.blur();'></span>";
	sObj.after(addStr);
	var btn = $("#addBtn_"+treeNode.tId);
	if (btn) btn.bind("click", function(){
                addRemoteNode(treeNode);
		//var zTree = $.fn.zTree.getZTreeObj("treeDemo");
		//zTree.addNodes(treeNode, {id:(1000000 + newCount), pId:treeNode.id, name:"new node" + (newCount++)});
		return false;
	});
};
function removeHoverDom(treeId, treeNode) {
	$("#addBtn_"+treeNode.tId).unbind().remove();
};


/* */

function onKeyEnter() {
        var zTree = $.fn.zTree.getZTreeObj("treeDemo");
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
        var zTree = $.fn.zTree.getZTreeObj("treeDemo");
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
        var zTree = $.fn.zTree.getZTreeObj("treeDemo");
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
        var zTree = $.fn.zTree.getZTreeObj("treeDemo");
	var nodes = zTree.getSelectedNodes();
	if(nodes.length > 0) {
		if(nodes[0].isParent && nodes[0].open == false) {
			zTree.expandNode(nodes[0], true);
		}
	}
}

function onKeyLeft() {
        var zTree = $.fn.zTree.getZTreeObj("treeDemo");
	var nodes = zTree.getSelectedNodes();
	if(nodes.length > 0) {
		if(nodes[0].isParent && nodes[0].open == true) {
			zTree.expandNode(nodes[0], false);
		}
	}
}

function onKeyShiftEnter() {
        var zTree = $.fn.zTree.getZTreeObj("treeDemo");
	var nodes = zTree.getSelectedNodes();
	if(nodes.length > 0) {
		if(nodes[0].getParentNode()) {
			addRemoteNode(nodes[0].getParentNode());
		}
	}
}

var treeHistory = [];

$(document).ready(function(){
	/*
	 * Key combos: by default, no node is selected... Enter will be used to either
	 * select the top node or create a new node
	 */
	var bindings = new Keys.Bindings();
	bindings.add('onKeyEnter', new Keys.Combo(Keys.Key.Enter));
        bindings.registerHandler(onKeyEnter);
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

	$.fn.zTree.init($("#treeDemo"), setting);
        /*
         * If back arrow clicked, then pop tree history
         */
	$("#backintree").click(function() {
          if(treeHistory.length > 0) {
	    setting.async.otherParam.queryParent = treeHistory.pop();
	    $.fn.zTree.init($("#treeDemo"), setting);
          }
	});
});
