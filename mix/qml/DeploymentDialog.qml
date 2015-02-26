import QtQuick 2.2
import QtQuick.Controls 1.1
import QtQuick.Layouts 1.1
import QtQuick.Window 2.0
import QtQuick.Dialogs 1.1
import QtQuick.Controls.Styles 1.3
import org.ethereum.qml.QEther 1.0
import "js/TransactionHelper.js" as TransactionHelper
import "js/ProjectModel.js" as ProjectModelCode
import "js/QEtherHelper.js" as QEtherHelper
import "."


Window {
	id: modalDeploymentDialog
	modality: Qt.ApplicationModal
	width: 600
	height: 350
	visible: false
	property alias applicationUrlEth: applicationUrlEth.text
	property alias applicationUrlHttp: applicationUrlHttp.text
	property string urlHintContract: "0000000000000000000000000000000000000a29"
	property string packageHash
	property alias packageBase64: base64Value.text
	property string eth: "0000000000000000000000000000000000000a28";
	property string wallet: "0000000000000000000000000000000000000a29";

	color: Style.generic.layout.backgroundColor

	function close()
	{
		visible = false;
	}

	function open()
	{
		modalDeploymentDialog.setX((Screen.width - width) / 2);
		modalDeploymentDialog.setY((Screen.height - height) / 2);
		visible = true;
	}

	function pad(h)
	{
		// TODO move this to QHashType class
		while (h.length < 64)
		{
			h = '0' + h;
		}
		return h;
	}

	Rectangle
	{
		anchors.fill : parent
		anchors.margins: 10
		color: Style.generic.layout.backgroundColor
		GridLayout
		{
			columns: 2
			anchors.top: parent.top
			anchors.left: parent.left
			width: parent.width
			DefaultLabel
			{
				text: qsTr("Ethereum Application URL: ")
			}

			DefaultTextField
			{
				Layout.fillWidth: true
				id: applicationUrlEth
			}

			DefaultLabel
			{
				text: qsTr("Web Application Ressources URL: ")
			}

			DefaultTextField
			{
				Layout.fillWidth: true
				id: applicationUrlHttp
			}

			DefaultLabel
			{
				text: qsTr("Package (Base64): ")
			}

			TextArea
			{
				Layout.fillWidth: true
				readOnly: true
				id: base64Value
				height: 60
				enabled: base64Value.text != ""
			}
		}

		MessageDialog {
			id: deployDialog
			standardButtons: StandardButton.Ok
			icon: StandardIcon.Warning
		}

		RowLayout
		{
			anchors.bottom: parent.bottom
			anchors.right: parent.right;
			anchors.bottomMargin: 10
			Button {
				text: qsTr("Deploy to Ethereum");
				tooltip: qsTr("Deploy contract and package resources files.")
				onClicked: {
					deployWarningDialog.open();
				}
			}

			Button {
				text: qsTr("Register Web Application");
				tooltip: qsTr("Register hosted Web Application.")
				onClicked: {
					if (applicationUrlHttp.text === "" || deploymentDialog.packageHash === "")
					{
						deployDialog.title = text;
						deployDialog.text = qsTr("Please provide the link where the resources are stored and ensure the package is aleary built using the deployment step. ")
						deployDialog.open();
					}
					else
						ProjectModelCode.registerToUrlHint();
				}
			}

			Button {
				text: qsTr("Close");
				onClicked: close();
			}

			Button {
				text: qsTr("Check Ownership");
				visible : false
				onClicked: {
					var requests = [];
					var ethStr = QEtherHelper.createString("wallet");

					var ethHash = QEtherHelper.createHash(eth);

					requests.push({ //owner
					jsonrpc: "2.0",
					method: "eth_call",
					params: [ { "to": '0x' + modalDeploymentDialog.eth, "data": "0xec7b9200" + ethStr.encodeValueAsString() } ],
					id: 3
				});

				requests.push({ //register
					jsonrpc: "2.0",
					method: "eth_call",
					params: [ { "to":  '0x' + modalDeploymentDialog.eth, "data": "0x6be16bed" + ethStr.encodeValueAsString() } ],
					id: 4
				});

					var jsonRpcUrl = "http://localhost:8080";
					var rpcRequest = JSON.stringify(requests);
					var httpRequest = new XMLHttpRequest();
					httpRequest.open("POST", jsonRpcUrl, true);
					httpRequest.setRequestHeader("Content-type", "application/json");
					httpRequest.setRequestHeader("Content-length", rpcRequest.length);
					httpRequest.setRequestHeader("Connection", "close");
					httpRequest.onreadystatechange = function() {
						if (httpRequest.readyState === XMLHttpRequest.DONE) {
							if (httpRequest.status === 200) {
								console.log(httpRequest.responseText);
							} else {
								var errorText = qsTr("path registration failed ") + httpRequest.status;
								console.log(errorText);
							}
						}
					}
					httpRequest.send(rpcRequest);
				}
			}


			Button {
				text: qsTr("Generate registrar init");
				visible: false
				onClicked: {
					console.log("registering eth/wallet")
					var jsonRpcRequestId = 0;

					var requests = [];

					var walletStr = QEtherHelper.createString("wallet");

					requests.push({ //reserve
									  jsonrpc: "2.0",
									  method: "eth_transact",
									  params: [ { "to": '0x' + modalDeploymentDialog.eth, "data": "0x1c83171b" + walletStr.encodeValueAsString() } ],
									  id: jsonRpcRequestId++
								  });


					requests.push({ //setRegister
									  jsonrpc: "2.0",
									  method: "eth_transact",
									  params: [ { "to": '0x' + modalDeploymentDialog.eth, "data": "0x96077307" + walletStr.encodeValueAsString() + pad(wallet) } ],
									  id: jsonRpcRequestId++
								  });

					var jsonRpcUrl = "http://localhost:8080";
					var rpcRequest = JSON.stringify(requests);
					var httpRequest = new XMLHttpRequest();
					httpRequest.open("POST", jsonRpcUrl, true);
					httpRequest.setRequestHeader("Content-type", "application/json");
					httpRequest.setRequestHeader("Content-length", rpcRequest.length);
					httpRequest.setRequestHeader("Connection", "close");
					httpRequest.onreadystatechange = function() {
						if (httpRequest.readyState === XMLHttpRequest.DONE) {
							if (httpRequest.status === 200) {
								console.log(httpRequest.responseText);
							} else {
								var errorText = qsTr("path registration failed ") + httpRequest.status;
								console.log(errorText);
							}
						}
					}
					httpRequest.send(rpcRequest);
				}
			}
		}
	}
}
