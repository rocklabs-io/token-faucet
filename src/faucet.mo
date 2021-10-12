/**
 * Module     : faucet.mo
 * Copyright  : 2021 DFinance Team
 * License    : Apache 2.0 with LLVM Exception
 * Maintainer : DFinance Team <hello@dfinance.ai>
 * Stability  : Experimental
 */

import HashMap "mo:base/HashMap";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Hash "mo:base/Hash";
import Error "mo:base/Error";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Cycles "mo:base/ExperimentalCycles";
import Nat8 "mo:base/Nat8";
import Result "mo:base/Result";

shared(msg) actor class Faucet(_owner: Principal) = this {
    type TxReceipt = Result.Result<Nat, {
        #InsufficientBalance;
        #InsufficientAllowance;
    }>;
    public type TokenActor = actor {
        allowance: shared (owner: Principal, spender: Principal) -> async Nat;
        approve: shared (spender: Principal, value: Nat) -> async TxReceipt;
        balanceOf: (owner: Principal) -> async Nat;
        decimals: () -> async Nat8;
        name: () -> async Text;
        symbol: () -> async Text;
        totalSupply: () -> async Nat;
        transfer: shared (to: Principal, value: Nat) -> async TxReceipt;
        transferFrom: shared (from: Principal, to: Principal, value: Nat) -> async TxReceipt;
    };

    private stable var owner: Principal = _owner;

    public type Stats = {
        owner: Principal;
        cycles: Nat;
        tokenPerUser: Nat;
        userNumber: Nat;
        // recordEntries: [(Principal, [(Principal, Nat)])];
    };

    private stable var tokenPerUser: Nat = 100;

    private stable var recordEntries : [(Principal, [(Principal, Nat)])] = [];
    // User => Token => Amount
    private var records = HashMap.HashMap<Principal, HashMap.HashMap<Principal, Nat>>(1, Principal.equal, Principal.hash);

    private func _getRecordEntries(): [(Principal, [(Principal, Nat)])] {
        var size : Nat = records.size();
        var temp : [var (Principal, [(Principal, Nat)])] = Array.init<(Principal, [(Principal, Nat)])>(size, (owner, []));
        size := 0;
        for ((k, v) in records.entries()) {
            temp[size] := (k, Iter.toArray(v.entries()));
            size += 1;
        };
        return Array.freeze(temp);
    };

    system func preupgrade() {
        recordEntries := _getRecordEntries();
    };

    system func postupgrade() {
        for ((k, v) in recordEntries.vals()) {
            let record_temp = HashMap.fromIter<Principal, Nat>(v.vals(), 1, Principal.equal, Principal.hash);
            records.put(k, record_temp);
        };
        recordEntries := [];
    };

    private func _record(user: Principal, token: Principal) : Nat {
        switch(records.get(user)) {
            case (?user_record) {
                switch(user_record.get(token)) {
                    case (?amount) { return amount; };
                    case (_) { return 0; };
                }
            };
            case (_) { return 0; };
        }
    };

    public shared(msg) func getStats(): async Stats {
        // assert(msg.caller == owner);
        return {
            owner = owner;
            cycles = Cycles.balance();
            tokenPerUser = tokenPerUser;
            userNumber = records.size();
            // recordEntries = _getRecordEntries();
        };
    };

    public shared(msg) func getRecords(): async [(Principal, [(Principal, Nat)])] {
        assert(msg.caller == owner);
        _getRecordEntries()
    };

    public shared(msg) func setTokenPerUser(amount: Nat) {
        assert(msg.caller == owner);
        tokenPerUser := amount;
    };

    public query func claimed(token_id: Principal, a: Principal): async Bool {
        let amount = _record(a, token_id);
        if (amount >= tokenPerUser) {
            return true;
        };
        return false;
    };

    public shared(msg) func getToken(token_id: Principal): async TxReceipt {
        let amount = _record(msg.caller, token_id);
        if (amount >= tokenPerUser) {
            return #err(#InsufficientAllowance);
        };
        // add record
        if (Option.isNull(records.get(msg.caller))) {
            var temp = HashMap.HashMap<Principal, Nat>(1, Principal.equal, Principal.hash);
            temp.put(token_id, tokenPerUser);
            records.put(msg.caller, temp);
        } else {
            let record_caller = Option.unwrap(records.get(msg.caller));
            record_caller.put(token_id, tokenPerUser);
            records.put(msg.caller, record_caller);
        };
        // transfer token to msg.caller
        let token: TokenActor = actor(Principal.toText(token_id));
        let decimals: Nat8 = await token.decimals();
        return await token.transfer(msg.caller, tokenPerUser * 10**Nat8.toNat(decimals));
    };
}