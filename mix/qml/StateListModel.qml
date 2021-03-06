import QtQuick 2.2
import QtQuick.Controls 1.1
import QtQuick.Controls.Styles 1.1
import QtQuick.Dialogs 1.1
import QtQuick.Window 2.2
import QtQuick.Layouts 1.1
import org.ethereum.qml.QEther 1.0
import "js/QEtherHelper.js" as QEtherHelper
import "js/TransactionHelper.js" as TransactionHelper

Item {

	property alias model: stateListModel
	property var stateList: []
	property string defaultAccount: "cb73d9408c4720e230387d956eb0f829d8a4dd2c1055f96257167e14e7169074" //support for old project

	function fromPlainStateItem(s) {
		if (!s.accounts)
			s.accounts = [stateListModel.newAccount("1000000", QEther.Ether, defaultAccount)]; //support for old project
		return {
			title: s.title,
			transactions: s.transactions.map(fromPlainTransactionItem),
			accounts: s.accounts.map(fromPlainAccountItem)
		};
	}

	function fromPlainAccountItem(t)
	{
		return {
			name: t.name,
			secret: t.secret,
			balance: QEtherHelper.createEther(t.balance.value, t.balance.unit)
		};
	}

	function fromPlainTransactionItem(t) {
		if (!t.sender)
			t.sender = defaultAccount; //support for old project
		var r = {
			contractId: t.contractId,
			functionId: t.functionId,
			url: t.url,
			value: QEtherHelper.createEther(t.value.value, t.value.unit),
			gas: QEtherHelper.createBigInt(t.gas.value),
			gasPrice: QEtherHelper.createEther(t.gasPrice.value, t.gasPrice.unit),
			stdContract: t.stdContract ? true : false,
			parameters: {},
			sender: t.sender
		};
		for (var key in t.parameters)
			r.parameters[key] = t.parameters[key];

		return r;
	}

	function toPlainStateItem(s) {
		return {
			title: s.title,
			transactions: s.transactions.map(toPlainTransactionItem),
			accounts: s.accounts.map(toPlainAccountItem)
		};
	}

	function getParamType(param, params)
	{
		for (var k in params)
		{
			if (params[k].declaration.name === param)
				return params[k].declaration.type;
		}
		return '';
	}

	function toPlainAccountItem(t)
	{
		return {
			name: t.name,
			secret: t.secret,
			balance: {
				value: t.balance.value,
				unit: t.balance.unit
			}
		};
	}

	function toPlainTransactionItem(t) {
		var r = {
			contractId: t.contractId,
			functionId: t.functionId,
			url: t.url,
			value: { value: t.value.value, unit: t.value.unit },
			gas: { value: t.gas.value() },
			gasPrice: { value: t.gasPrice.value, unit: t.gasPrice.unit },
			stdContract: t.stdContract,
			parameters: {}
		};
		for (var key in t.parameters)
			r.parameters[key] = t.parameters[key];
		return r;
	}

	Connections {
		target: projectModel
		onProjectClosed: {
			stateListModel.clear();
			stateList = [];
			codeModel.reset();
		}
		onProjectLoading: stateListModel.loadStatesFromProject(projectData);
		onProjectFileSaving: {
			projectData.states = []
			for(var i = 0; i < stateListModel.count; i++) {
				projectData.states.push(toPlainStateItem(stateList[i]));
			}
			projectData.defaultStateIndex = stateListModel.defaultStateIndex;
		}
		onNewProject: {
			var state = toPlainStateItem(stateListModel.createDefaultState());
			state.title = qsTr("Default");
			projectData.states = [ state ];
			projectData.defaultStateIndex = 0;
			stateListModel.loadStatesFromProject(projectData);
		}
	}

	Connections {
		target: codeModel
		onNewContractCompiled: {
			stateListModel.addNewContracts();
		}
		onContractRenamed: {
			stateListModel.renameContracts(_oldName, _newName);
		}
	}

	StateDialog {
		id: stateDialog
		onAccepted: {
			var item = stateDialog.getItem();
			if (stateDialog.stateIndex < stateListModel.count) {
				if (stateDialog.isDefault)
					stateListModel.defaultStateIndex = stateIndex;
				stateList[stateDialog.stateIndex] = item;
				stateListModel.set(stateDialog.stateIndex, item);
			} else {
				if (stateDialog.isDefault)
					stateListModel.defaultStateIndex = 0;
				stateList.push(item);
				stateListModel.append(item);
			}
			if (stateDialog.isDefault)
				stateListModel.defaultStateChanged();
			stateListModel.save();
		}
	}

	ContractLibrary {
		id: contractLibrary;
	}

	ListModel {
		id: stateListModel
		property int defaultStateIndex: 0
		signal defaultStateChanged;
		signal stateListModelReady;
		signal stateRun(int index)

		function defaultTransactionItem() {
			return TransactionHelper.defaultTransaction();
		}

		function newAccount(_balance, _unit, _secret)
		{
			if (!_secret)
				_secret = clientModel.newAddress();
			var name = qsTr("Account") + "-" + _secret.substring(0, 4);
			return { name: name, secret: _secret, balance: QEtherHelper.createEther(_balance, _unit) };
		}

		function createDefaultState() {
			var item = {
				title: "",
				transactions: [],
				accounts: []
			};

			item.accounts.push(newAccount("1000000", QEther.Ether, defaultAccount));

			//add all stdc contracts
			for (var i = 0; i < contractLibrary.model.count; i++) {
				var contractTransaction = defaultTransactionItem();
				var contractItem = contractLibrary.model.get(i);
				contractTransaction.url = contractItem.url;
				contractTransaction.contractId = contractItem.name;
				contractTransaction.functionId = contractItem.name;
				contractTransaction.stdContract = true;
				contractTransaction.sender = item.accounts[0].secret; // default account is used to deploy std contract.
				item.transactions.push(contractTransaction);
			};

			//add constructors, //TODO: order by dependencies
			for(var c in codeModel.contracts) {
				var ctorTr = defaultTransactionItem();
				ctorTr.functionId = c;
				ctorTr.contractId = c;
				ctorTr.sender = item.accounts[0].secret;
				item.transactions.push(ctorTr);
			}
			return item;
		}

		function renameContracts(oldName, newName) {
			var changed = false;
			for(var c in codeModel.contracts) {
				for (var s = 0; s < stateListModel.count; s++) {
					var state = stateList[s];
					for (var t = 0; t < state.transactions.length; t++) {
						var transaction = state.transactions[t];
						if (transaction.contractId === oldName) {
							transaction.contractId = newName;
							if (transaction.functionId === oldName)
								transaction.functionId = newName;
							changed = true;
							state.transactions[t] = transaction;
						}
					}
					stateListModel.set(s, state);
					stateList[s] = state;
				}
			}
			if (changed)
				save();
		}

		function addNewContracts() {
			//add new contracts for all states
			var changed = false;
			for(var c in codeModel.contracts) {
				for (var s = 0; s < stateListModel.count; s++) {
					var state = stateList[s];
					for (var t = 0; t < state.transactions.length; t++) {
						var transaction = state.transactions[t];
						if (transaction.functionId === c && transaction.contractId === c)
							break;
					}
					if (t === state.transactions.length) {
						//append this contract
						var ctorTr = defaultTransactionItem();
						ctorTr.functionId = c;
						ctorTr.contractId = c;
						ctorTr.sender = state.accounts[0].secret;
						state.transactions.push(ctorTr);
						changed = true;
						stateListModel.set(s, state);
						stateList[s] = state;
					}
				}
			}
			if (changed)
				save();
		}

		function addState() {
			var item = createDefaultState();
			stateDialog.open(stateListModel.count, item, false);
		}

		function editState(index) {
			stateDialog.open(index, stateList[index], defaultStateIndex === index);
		}

		function debugDefaultState() {
			if (defaultStateIndex >= 0 && defaultStateIndex < stateList.length)
				runState(defaultStateIndex);
		}

		function runState(index) {
			var item = stateList[index];
			clientModel.setupState(item);
			stateRun(index);
		}

		function deleteState(index) {
			stateListModel.remove(index);
			stateList.splice(index, 1);
			if (index === defaultStateIndex)
			{
				defaultStateIndex = 0;
				defaultStateChanged();
			}
			else if (defaultStateIndex > index)
				defaultStateIndex--;

			save();

		}

		function save() {
			projectModel.saveProject();
		}

		function defaultStateName()
		{
			return stateList[defaultStateIndex].title;
		}

		function loadStatesFromProject(projectData)
		{
			if (!projectData.states)
				projectData.states = [];
			if (projectData.defaultStateIndex !== undefined)
				defaultStateIndex = projectData.defaultStateIndex;
			else
				defaultStateIndex = 0;
			var items = projectData.states;
			stateListModel.clear();
			stateList = [];
			for(var i = 0; i < items.length; i++) {
				var item = fromPlainStateItem(items[i]);
				stateListModel.append(item);
				stateList.push(item);
			}
			stateListModelReady();
		}
	}
}
