import QtQuick 2.2
import QtQuick.Controls 1.1
import QtQuick.Controls.Styles 1.1
import QtQuick.Dialogs 1.1
import QtQuick.Layouts 1.1
import org.ethereum.qml.RecordLogEntry 1.0

Item {

	property ListModel fullModel: ListModel{}
	property ListModel transactionModel: ListModel{}
	property ListModel callModel: ListModel{}

	Action {
		id: addStateAction
		text: "Add State"
		shortcut: "Ctrl+Alt+T"
		enabled: codeModel.hasContract && !clientModel.running;
		onTriggered: projectModel.stateListModel.addState();
	}
	Action {
		id: editStateAction
		text: "Edit State"
		shortcut: "Ctrl+Alt+T"
		enabled: codeModel.hasContract && !clientModel.running && statesCombo.currentIndex >= 0 && projectModel.stateListModel.count > 0;
		onTriggered: projectModel.stateListModel.editState(statesCombo.currentIndex);
	}

	ColumnLayout {
		anchors.fill: parent
		RowLayout {

			Connections
			{
				id: compilationStatus
				target: codeModel
				property bool compilationComplete: false
				onCompilationComplete: compilationComplete = true
				onCompilationError: compilationComplete = false
			}

			Connections
			{
				target: projectModel
				onProjectSaved:
				{
					if (projectModel.appIsClosing)
						return;
					if (compilationStatus.compilationComplete && codeModel.hasContract && !clientModel.running)
						projectModel.stateListModel.debugDefaultState();
				}
				onProjectClosed:
				{
					fullModel.clear();
					transactionModel.clear();
					callModel.clear();
				}
				onContractSaved: {
					if (compilationStatus.compilationComplete && codeModel.hasContract && !clientModel.running)
						projectModel.stateListModel.debugDefaultState();
				}
			}

			ComboBox {
				id: statesCombo
				model: projectModel.stateListModel
				width: 150
				editable: false
				textRole: "title"
				onActivated:  {
					model.runState(index);
				}
				Connections {
					target: projectModel.stateListModel
					onStateRun: {
						if (statesCombo.currentIndex !== index)
							statesCombo.currentIndex = index;
					}
				}
			}
			Button
			{
				anchors.rightMargin: 9
				anchors.verticalCenter: parent.verticalCenter
				action: editStateAction
			}
			Button
			{
				anchors.rightMargin: 9
				anchors.verticalCenter: parent.verticalCenter
				action: addStateAction
			}
			Button
			{
				anchors.rightMargin: 9
				anchors.verticalCenter: parent.verticalCenter
				action: mineAction
			}

			ComboBox {
				id: itemFilter

				function getCurrentModel()
				{
					return currentIndex === 0 ? fullModel : currentIndex === 1 ? transactionModel : currentIndex === 2 ? callModel : fullModel;
				}

				model: ListModel {
					ListElement { text: qsTr("Calls and Transactions"); value: 0;  }
					ListElement { text: qsTr("Only Transactions"); value: 1;  }
					ListElement { text: qsTr("Only Calls"); value: 2;  }
				}

				onCurrentIndexChanged:
				{
					logTable.model = itemFilter.getCurrentModel();
				}
			}
		}
		TableView {
			id: logTable
			Layout.fillWidth: true
			Layout.fillHeight: true
			model: fullModel

			TableViewColumn {
				role: "transactionIndex"
				title: qsTr("#")
				width: 40
			}
			TableViewColumn {
				role: "contract"
				title: qsTr("Contract")
				width: 100
			}
			TableViewColumn {
				role: "function"
				title: qsTr("Function")
				width: 120
			}
			TableViewColumn {
				role: "value"
				title: qsTr("Value")
				width: 60
			}
			TableViewColumn {
				role: "address"
				title: qsTr("Destination")
				width: 130
			}
			TableViewColumn {
				role: "returned"
				title: qsTr("Returned")
				width: 120
			}
			onActivated:  {
				var item = logTable.model.get(row);
				if (item.type === RecordLogEntry.Transaction)
					clientModel.debugRecord(item.recordIndex);
				else
					clientModel.emptyRecord();
			}
			Keys.onPressed: {
				if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && currentRow >=0 && currentRow < logTable.model.count) {
					var item = logTable.model.get(currentRow);
					clipboard.text = item.returned;
				}
			}
		}
		Rectangle {
			height: 6
			color: "transparent"
		}
	}

	Connections {
		target: clientModel
		onStateCleared: {
			fullModel.clear();
			transactionModel.clear();
			callModel.clear();
		}
		onNewRecord: {
			fullModel.append(_r);
			if (!_r.call)
				transactionModel.append(_r);
			else
				callModel.append(_r);
		}
		onMiningComplete: {
			fullModel.append(clientModel.lastBlock);
			transactionModel.append(clientModel.lastBlock);
		}
	}
}
