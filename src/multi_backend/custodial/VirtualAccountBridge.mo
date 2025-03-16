import Principal "mo:base/Principal";
import Debug "mo:base/Debug";

import Types "../types/Types";
import VirtualAccounts "./VirtualAccounts";
import AmountOperations "../financial/AmountOperations";

module {
  public func transfer(
    source : VirtualAccounts.VirtualAccounts,
    destination : VirtualAccounts.VirtualAccounts,
    account : Types.Account,
    amount : Types.Amount,
  ) {
    let sourceBalance = source.getBalance(account, amount.token);
    if (sourceBalance.value < amount.value) {
      Debug.trap("Insufficient balance for transfer: required=" # debug_show (amount.value) # ", balance=" # debug_show (sourceBalance.value));
    };

    if (amount.value == 0) {
      Debug.trap("Cannot transfer zero amount");
    };

    source.burn(account, amount);
    destination.mint(account, amount);
  };
};
