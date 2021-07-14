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
import Nat64 "mo:base/Nat64";
import Hash "mo:base/Hash";
import Error "mo:base/Error";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Cycles = "mo:base/ExperimentalCycles";

shared(msg) actor class Faucet() = this {

    public type TokenActor = actor {
        allowance: shared (owner: Principal, spender: Principal) -> async Nat64;
        approve: shared (spender: Principal, value: Nat64) -> async Bool;
        balanceOf: (owner: Principal) -> async Nat64;
        decimals: () -> async Nat64;
        name: () -> async Text;
        symbol: () -> async Text;
        totalSupply: () -> async Nat64;
        transfer: shared (to: Principal, value: Nat64) -> async Bool;
        transferFrom: shared (from: Principal, to: Principal, value: Nat64) -> async Bool;
    };

    private stable var owner: Principal = msg.caller;

    public type Stats = {
        owner: Principal;
        cycles: Nat;
        tokenPerUser: Nat64;
        recordEntries: [(Principal, [(Principal, Nat64)])];
    };

    private stable var tokenPerUser: Nat64 = 10;

    private stable var recordEntries : [(Principal, [(Principal, Nat64)])] = [];
    // User => Token => Amount
    private var records = HashMap.HashMap<Principal, HashMap.HashMap<Principal, Nat64>>(1, Principal.equal, Principal.hash);

    private func _getRecordEntries(): [(Principal, [(Principal, Nat64)])] {
        var size : Nat = records.size();
        var temp : [var (Principal, [(Principal, Nat64)])] = Array.init<(Principal, [(Principal, Nat64)])>(size, (owner, []));
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
            let record_temp = HashMap.fromIter<Principal, Nat64>(v.vals(), 1, Principal.equal, Principal.hash);
            records.put(k, record_temp);
        };
        recordEntries := [];
    };

    private func _record(user: Principal, token: Principal) : Nat64 {
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
            recordEntries = _getRecordEntries();
        };
    };

    public shared(msg) func setTokenPerUser(amount: Nat64) {
        assert(msg.caller == owner);
        tokenPerUser := amount;
    };

    public shared(msg) func getToken(token_id: Principal): async Bool {
        let amount = _record(msg.caller, token_id);
        if (amount >= tokenPerUser) {
            return false;
        };
        // add record
        if (Option.isNull(records.get(msg.caller))) {
            var temp = HashMap.HashMap<Principal, Nat64>(1, Principal.equal, Principal.hash);
            temp.put(token_id, tokenPerUser);
            records.put(msg.caller, temp);
        } else {
            let record_caller = Option.unwrap(records.get(msg.caller));
            record_caller.put(token_id, tokenPerUser);
            records.put(msg.caller, record_caller);
        };
        // transfer token to msg.caller
        let token: TokenActor = actor(Principal.toText(token_id));
        let decimals: Nat64 = await token.decimals();
        return await token.transfer(msg.caller, tokenPerUser * 10**decimals);
    };
}