/*
	This file is part of cpp-ethereum.

	cpp-ethereum is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	cpp-ethereum is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with cpp-ethereum.  If not, see <http://www.gnu.org/licenses/>.
*/
/** @file MixClient.cpp
 * @author Arkadiy Paronyan arkadiy@ethdev.com
 * @date 2015
 * Ethereum IDE client.
 */

#include <vector>
#include <libdevcore/Exceptions.h>
#include <libethereum/CanonBlockChain.h>
#include <libethereum/Transaction.h>
#include <libethereum/Executive.h>
#include <libethereum/ExtVM.h>
#include <libethereum/BlockChain.h>
#include <libevm/VM.h>

#include "Exceptions.h"
#include "MixClient.h"

using namespace dev;
using namespace dev::eth;

namespace dev
{
namespace mix
{

// TODO: merge as much as possible with the Client.cpp into a mutually inherited base class.

const Secret c_defaultUserAccountSecret = Secret("cb73d9408c4720e230387d956eb0f829d8a4dd2c1055f96257167e14e7169074");
const u256 c_mixGenesisDifficulty = c_minimumDifficulty; //TODO: make it lower for Mix somehow

class MixBlockChain: public dev::eth::BlockChain
{
public:
	MixBlockChain(std::string const& _path, h256 _stateRoot):
		BlockChain(createGenesisBlock(_stateRoot), _path, true)
	{
	}

	static bytes createGenesisBlock(h256 _stateRoot)
	{
		RLPStream block(3);
		block.appendList(15)
			<< h256() << EmptyListSHA3 << h160() << _stateRoot << EmptyTrie << EmptyTrie
			<< LogBloom() << c_mixGenesisDifficulty << 0 << c_genesisGasLimit << 0 << (unsigned)0
			<< std::string() << h256() << h64(u64(42));
		block.appendRaw(RLPEmptyList);
		block.appendRaw(RLPEmptyList);
		return block.out();
	}
};

MixClient::MixClient(std::string const& _dbPath):
	m_dbPath(_dbPath), m_minigThreads(0)
{
	std::map<Secret, u256> account;
	account.insert(std::make_pair(c_defaultUserAccountSecret, 1000000 * ether));
	resetState(account);
}

MixClient::~MixClient()
{
}

void MixClient::resetState(std::map<Secret, u256> _accounts)
{
	WriteGuard l(x_state);
	Guard fl(m_filterLock);
	m_filters.clear();
	m_watches.clear();

	m_stateDB = OverlayDB();
	SecureTrieDB<Address, MemoryDB> accountState(&m_stateDB);
	accountState.init();

	std::map<Address, Account> genesisState;
	for (auto account: _accounts)
	{
		KeyPair a = KeyPair(account.first);
		m_userAccounts.push_back(a);
		genesisState.insert(std::make_pair(a.address(), Account(account.second, Account::NormalCreation)));
	}

	dev::eth::commit(genesisState, static_cast<MemoryDB&>(m_stateDB), accountState);
	h256 stateRoot = accountState.root();
	m_bc.reset();
	m_bc.reset(new MixBlockChain(m_dbPath, stateRoot));
	m_state = eth::State(genesisState.begin()->first , m_stateDB, BaseState::Empty);
	m_state.sync(bc());
	m_startState = m_state;
	WriteGuard lx(x_executions);
	m_executions.clear();
}

void MixClient::executeTransaction(Transaction const& _t, State& _state, bool _call)
{
	bytes rlp = _t.rlp();

	// do debugging run first
	LastHashes lastHashes(256);
	lastHashes[0] = bc().numberHash(bc().number());
	for (unsigned i = 1; i < 256; ++i)
		lastHashes[i] = lastHashes[i - 1] ? bc().details(lastHashes[i - 1]).parent : h256();

	State execState = _state;
	Executive execution(execState, lastHashes, 0);
	execution.setup(&rlp);
	std::vector<MachineState> machineStates;
	std::vector<unsigned> levels;
	std::vector<MachineCode> codes;
	std::map<bytes const*, unsigned> codeIndexes;
	std::vector<bytes> data;
	std::map<bytesConstRef const*, unsigned> dataIndexes;
	bytes const* lastCode = nullptr;
	bytesConstRef const* lastData = nullptr;
	unsigned codeIndex = 0;
	unsigned dataIndex = 0;
	auto onOp = [&](uint64_t steps, Instruction inst, dev::bigint newMemSize, dev::bigint gasCost, void* voidVM, void const* voidExt)
	{
		VM& vm = *static_cast<VM*>(voidVM);
		ExtVM const& ext = *static_cast<ExtVM const*>(voidExt);
		if (lastCode == nullptr || lastCode != &ext.code)
		{
			auto const& iter = codeIndexes.find(&ext.code);
			if (iter != codeIndexes.end())
				codeIndex = iter->second;
			else
			{
				codeIndex = codes.size();
				codes.push_back(MachineCode({ext.myAddress, ext.code}));
				codeIndexes[&ext.code] = codeIndex;
			}
			lastCode = &ext.code;
		}

		if (lastData == nullptr || lastData != &ext.data)
		{
			auto const& iter = dataIndexes.find(&ext.data);
			if (iter != dataIndexes.end())
				dataIndex = iter->second;
			else
			{
				dataIndex = data.size();
				data.push_back(ext.data.toBytes());
				dataIndexes[&ext.data] = dataIndex;
			}
			lastData = &ext.data;
		}

		if (levels.size() < ext.depth)
			levels.push_back(machineStates.size() - 1);
		else
			levels.resize(ext.depth);

		machineStates.emplace_back(MachineState({steps, vm.curPC(), inst, newMemSize, vm.gas(),
									  vm.stack(), vm.memory(), gasCost, ext.state().storage(ext.myAddress), levels, codeIndex, dataIndex}));
	};

	execution.go(onOp);
	execution.finalize();

	ExecutionResult d;
	d.result = execution.executionResult();
	d.machineStates = machineStates;
	d.executionCode = std::move(codes);
	d.transactionData = std::move(data);
	d.address = _t.receiveAddress();
	d.sender = _t.sender();
	d.value = _t.value();
	if (_t.isCreation())
		d.contractAddress = right160(sha3(rlpList(_t.sender(), _t.nonce())));
	if (!_call)
		d.transactionIndex = m_state.pending().size();
	d.executonIndex = m_executions.size();

	// execute on a state
	if (!_call)
	{
		_state.execute(lastHashes, rlp);
		if (_t.isCreation() && _state.code(d.contractAddress).empty())
			BOOST_THROW_EXCEPTION(OutOfGas() << errinfo_comment("Not enough gas for contract deployment"));
		// collect watches
		h256Set changed;
		Guard l(m_filterLock);
		for (std::pair<h256 const, eth::InstalledFilter>& i: m_filters)
			if ((unsigned)i.second.filter.latest() > bc().number())
			{
				// acceptable number.
				auto m = i.second.filter.matches(_state.receipt(_state.pending().size() - 1));
				if (m.size())
				{
					// filter catches them
					for (LogEntry const& l: m)
						i.second.changes.push_back(LocalisedLogEntry(l, bc().number() + 1));
					changed.insert(i.first);
				}
			}
		changed.insert(dev::eth::PendingChangedFilter);
		noteChanged(changed);
	}
	WriteGuard l(x_executions);
	m_executions.emplace_back(std::move(d));
}

void MixClient::mine()
{
	WriteGuard l(x_state);
	m_state.commitToMine(bc());
	while (!m_state.mine(100, true).completed) {}
	m_state.completeMine();
	bc().import(m_state.blockData(), m_stateDB);
	m_state.sync(bc());
	m_startState = m_state;
	h256Set changed { dev::eth::PendingChangedFilter, dev::eth::ChainChangedFilter };
	noteChanged(changed);
}

ExecutionResult MixClient::lastExecution() const
{
	ReadGuard l(x_executions);
	return m_executions.empty() ? ExecutionResult() : m_executions.back();
}

ExecutionResult MixClient::execution(unsigned _index) const
{
	ReadGuard l(x_executions);
	return m_executions.at(_index);
}

State MixClient::asOf(int _block) const
{
	ReadGuard l(x_state);
	if (_block == 0)
		return m_state;
	else if (_block == -1)
		return m_startState;
	else
		return State(m_stateDB, bc(), bc().numberHash(_block));
}

void MixClient::submitTransaction(Secret _secret, u256 _value, Address _dest, bytes const& _data, u256 _gas, u256 _gasPrice)
{
	WriteGuard l(x_state);
	u256 n = m_state.transactionsFrom(toAddress(_secret));
	Transaction t(_value, _gasPrice, _gas, _dest, _data, n, _secret);
	executeTransaction(t, m_state, false);
}

Address MixClient::submitTransaction(Secret _secret, u256 _endowment, bytes const& _init, u256 _gas, u256 _gasPrice)
{
	WriteGuard l(x_state);
	u256 n = m_state.transactionsFrom(toAddress(_secret));
	eth::Transaction t(_endowment, _gasPrice, _gas, _init, n, _secret);
	executeTransaction(t, m_state, false);
	Address address = right160(sha3(rlpList(t.sender(), t.nonce())));
	return address;
}

void MixClient::inject(bytesConstRef _rlp)
{
	WriteGuard l(x_state);
	eth::Transaction t(_rlp, CheckSignature::None);
	executeTransaction(t, m_state, false);
}

void MixClient::flushTransactions()
{
}

dev::eth::ExecutionResult MixClient::call(Secret _secret, u256 _value, Address _dest, bytes const& _data, u256 _gas, u256 _gasPrice, int _blockNumber)
{
	u256 n;
	State temp;
	{
		ReadGuard lr(x_state);
		temp = asOf(_blockNumber);
		n = temp.transactionsFrom(toAddress(_secret));
	}
	Transaction t(_value, _gasPrice, _gas, _dest, _data, n, _secret);
	bytes rlp = t.rlp();
	WriteGuard lw(x_state); //TODO: lock is required only for last execution state
	executeTransaction(t, temp, true);
	return lastExecution().result;
}

dev::eth::ExecutionResult MixClient::create(Secret _secret, u256 _value, bytes const& _data, u256 _gas, u256 _gasPrice, int _blockNumber)
{
	u256 n;
	State temp;
	{
		ReadGuard lr(x_state);
		temp = asOf(_blockNumber);
		n = temp.transactionsFrom(toAddress(_secret));
	}
	Transaction t(_value, _gasPrice, _gas, _data, n, _secret);
	bytes rlp = t.rlp();
	WriteGuard lw(x_state); //TODO: lock is required only for last execution state
	executeTransaction(t, temp, true);
	return lastExecution().result;
}

u256 MixClient::balanceAt(Address _a, int _block) const
{
	return asOf(_block).balance(_a);
}

u256 MixClient::countAt(Address _a, int _block) const
{
	return asOf(_block).transactionsFrom(_a);
}

u256 MixClient::stateAt(Address _a, u256 _l, int _block) const
{
	return asOf(_block).storage(_a, _l);
}

bytes MixClient::codeAt(Address _a, int _block) const
{
	return asOf(_block).code(_a);
}

std::map<u256, u256> MixClient::storageAt(Address _a, int _block) const
{
	return asOf(_block).storage(_a);
}

eth::LocalisedLogEntries MixClient::logs(unsigned _watchId) const
{
	Guard l(m_filterLock);
	h256 h = m_watches.at(_watchId).id;
	auto filterIter = m_filters.find(h);
	if (filterIter != m_filters.end())
		return logs(filterIter->second.filter);
	return eth::LocalisedLogEntries();
}

eth::LocalisedLogEntries MixClient::logs(eth::LogFilter const& _f) const
{
	LocalisedLogEntries ret;
	unsigned lastBlock = bc().number();
	unsigned block = std::min<unsigned>(lastBlock, (unsigned)_f.latest());
	unsigned end = std::min(lastBlock, std::min(block, (unsigned)_f.earliest()));
	// Pending transactions
	if (block > bc().number())
	{
		ReadGuard l(x_state);
		for (unsigned i = 0; i < m_state.pending().size(); ++i)
		{
			// Might have a transaction that contains a matching log.
			TransactionReceipt const& tr = m_state.receipt(i);
			LogEntries logEntries = _f.matches(tr);
			for (unsigned entry = 0; entry < logEntries.size(); ++entry)
				ret.insert(ret.begin(), LocalisedLogEntry(logEntries[entry], block));
		}
		block = bc().number();
	}

	// The rest
	auto h = bc().numberHash(block);
	for (; ret.size() != block && block != end; block--)
	{
		if (_f.matches(bc().info(h).logBloom))
			for (TransactionReceipt receipt: bc().receipts(h).receipts)
				if (_f.matches(receipt.bloom()))
					for (auto const& e: _f.matches(receipt))
						ret.insert(ret.begin(), LocalisedLogEntry(e, block));
		h = bc().details(h).parent;
	}
	return ret;
}

unsigned MixClient::installWatch(h256 _h, eth::Reaping _r)
{
	unsigned ret;
	{
		Guard l(m_filterLock);
		ret = m_watches.size() ? m_watches.rbegin()->first + 1 : 0;
		m_watches[ret] = ClientWatch(_h, _r);
	}
	auto ch = logs(ret);
	if (ch.empty())
		ch.push_back(eth::InitialChange);
	{
		Guard l(m_filterLock);
		swap(m_watches[ret].changes, ch);
	}
	return ret;
}

unsigned MixClient::installWatch(eth::LogFilter const& _f, eth::Reaping _r)
{
	h256 h = _f.sha3();
	{
		Guard l(m_filterLock);
		m_filters.insert(std::make_pair(h, _f));
	}
	return installWatch(h, _r);
}

bool MixClient::uninstallWatch(unsigned _i)
{
	Guard l(m_filterLock);

	auto it = m_watches.find(_i);
	if (it == m_watches.end())
		return false;
	auto id = it->second.id;
	m_watches.erase(it);

	auto fit = m_filters.find(id);
	if (fit != m_filters.end())
		if (!--fit->second.refCount)
			m_filters.erase(fit);

	return true;
}

void MixClient::noteChanged(h256Set const& _filters)
{
	for (auto& i: m_watches)
		if (_filters.count(i.second.id))
		{
			if (m_filters.count(i.second.id))
				i.second.changes += m_filters.at(i.second.id).changes;
			else
				i.second.changes.push_back(LocalisedLogEntry(SpecialLogEntry, 0));
		}
	for (auto& i: m_filters)
		i.second.changes.clear();
}

LocalisedLogEntries MixClient::peekWatch(unsigned _watchId) const
{
	Guard l(m_filterLock);
	if (_watchId < m_watches.size())
		return m_watches.at(_watchId).changes;
	return LocalisedLogEntries();
}

LocalisedLogEntries MixClient::checkWatch(unsigned _watchId)
{
	Guard l(m_filterLock);
	LocalisedLogEntries ret;
	if (_watchId < m_watches.size())
		std::swap(ret, m_watches.at(_watchId).changes);
	return ret;
}

h256 MixClient::hashFromNumber(unsigned _number) const
{
	ReadGuard l(x_state);
	return bc().numberHash(_number);
}

eth::BlockInfo MixClient::blockInfo(h256 _hash) const
{
	ReadGuard l(x_state);
	return BlockInfo(bc().block(_hash));

}

eth::BlockInfo MixClient::blockInfo() const
{
	ReadGuard l(x_state);
	return BlockInfo(bc().block());
}

eth::BlockDetails MixClient::blockDetails(h256 _hash) const
{
	ReadGuard l(x_state);
	return bc().details(_hash);
}

Transaction MixClient::transaction(h256 _transactionHash) const
{
	ReadGuard l(x_state);
	return Transaction(bc().transaction(_transactionHash), CheckSignature::Range);
}

eth::Transaction MixClient::transaction(h256 _blockHash, unsigned _i) const
{
	ReadGuard l(x_state);
	auto bl = bc().block(_blockHash);
	RLP b(bl);
	if (_i < b[1].itemCount())
		return Transaction(b[1][_i].data(), CheckSignature::Range);
	else
		return Transaction();
}

eth::BlockInfo MixClient::uncle(h256 _blockHash, unsigned _i) const
{
	ReadGuard l(x_state);
	auto bl = bc().block(_blockHash);
	RLP b(bl);
	if (_i < b[2].itemCount())
		return BlockInfo::fromHeader(b[2][_i].data());
	else
		return BlockInfo();
}

unsigned MixClient::transactionCount(h256 _blockHash) const
{
	ReadGuard l(x_state);
	auto bl = bc().block(_blockHash);
	RLP b(bl);
	return b[1].itemCount();
}

unsigned MixClient::uncleCount(h256 _blockHash) const
{
	ReadGuard l(x_state);
	auto bl = bc().block(_blockHash);
	RLP b(bl);
	return b[2].itemCount();
}

Transactions MixClient::transactions(h256 _blockHash) const
{
	ReadGuard l(x_state);
	auto bl = bc().block(_blockHash);
	RLP b(bl);
	Transactions res;
	for (unsigned i = 0; i < b[1].itemCount(); i++)
		res.emplace_back(b[1][i].data(), CheckSignature::Range);
	return res;
}

TransactionHashes MixClient::transactionHashes(h256 _blockHash) const
{
	ReadGuard l(x_state);
	return bc().transactionHashes(_blockHash);
}

unsigned MixClient::number() const
{
	ReadGuard l(x_state);
	return bc().number();
}

eth::Transactions MixClient::pending() const
{
	ReadGuard l(x_state);
	return m_state.pending();
}

eth::StateDiff MixClient::diff(unsigned _txi, h256 _block) const
{
	ReadGuard l(x_state);
	State st(m_stateDB, bc(), _block);
	return st.fromPending(_txi).diff(st.fromPending(_txi + 1));
}

eth::StateDiff MixClient::diff(unsigned _txi, int _block) const
{
	State st = asOf(_block);
	return st.fromPending(_txi).diff(st.fromPending(_txi + 1));
}

Addresses MixClient::addresses(int _block) const
{
	Addresses ret;
	for (auto const& i: asOf(_block).addresses())
		ret.push_back(i.first);
	return ret;
}

u256 MixClient::gasLimitRemaining() const
{
	ReadGuard l(x_state);
	return m_state.gasLimitRemaining();
}

void MixClient::setAddress(Address _us)
{
	WriteGuard l(x_state);
	m_state.setAddress(_us);
}

Address MixClient::address() const
{
	ReadGuard l(x_state);
	return m_state.address();
}

void MixClient::setMiningThreads(unsigned _threads)
{
	m_minigThreads = _threads;
}

unsigned MixClient::miningThreads() const
{
	return m_minigThreads;
}

void MixClient::startMining()
{
	//no-op
}

void MixClient::stopMining()
{
	//no-op
}

bool MixClient::isMining()
{
	return false;
}

eth::MineProgress MixClient::miningProgress() const
{
	return eth::MineProgress();
}

}
}
