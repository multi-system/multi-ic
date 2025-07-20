import { Principal } from '@dfinity/principal';
import { showToast } from '../components/Toast';

// Type definitions matching your backend errors
export type CommonError =
  | { InvalidAmount: { amount: bigint; reason: string } }
  | { InvalidSupplyUnit: null }
  | { InsufficientBalance: { token: Principal; balance: bigint; required: bigint } }
  | { NotInitialized: null }
  | { InvalidSupplyChange: { currentSupply: bigint; requestedChange: bigint; reason: string } }
  | { LedgerError: string }
  | { Unauthorized: null }
  | { AlreadyInitialized: null }
  | { TokenNotApproved: Principal }
  | { TokenAlreadyApproved: Principal }
  | { Other: { code: bigint; message: string } }
  | { TokenError: { token: Principal; code: bigint; message: string } };

// Helper to safely stringify values containing BigInts
export function safeStringify(obj: any): string {
  return JSON.stringify(
    obj,
    (key, value) => {
      if (typeof value === 'bigint') {
        return value.toString();
      }
      if (value instanceof Principal || (value && typeof value.toText === 'function')) {
        return value.toText();
      }
      return value;
    },
    2
  );
}

// Format error for display
export function formatError(error: CommonError): { title: string; message?: string } {
  if ('InvalidAmount' in error) {
    const amount = Number(error.InvalidAmount.amount) / 1e8;
    return {
      title: 'Invalid Amount',
      message: `${amount.toFixed(8)} - ${error.InvalidAmount.reason}`,
    };
  }

  if ('InvalidSupplyUnit' in error) {
    return { title: 'Invalid Supply Unit' };
  }

  if ('InsufficientBalance' in error) {
    const balance = Number(error.InsufficientBalance.balance) / 1e8;
    const required = Number(error.InsufficientBalance.required) / 1e8;
    const token = error.InsufficientBalance.token.toText();
    return {
      title: 'Insufficient Balance',
      message: `Have ${balance.toFixed(2)}, need ${required.toFixed(2)} (Token: ${token.slice(0, 10)}...)`,
    };
  }

  if ('NotInitialized' in error) {
    return { title: 'System Not Initialized' };
  }

  if ('InvalidSupplyChange' in error) {
    const current = Number(error.InvalidSupplyChange.currentSupply) / 1e8;
    const requested = Number(error.InvalidSupplyChange.requestedChange) / 1e8;
    return {
      title: 'Invalid Supply Change',
      message: `Current: ${current.toFixed(2)}, Requested: ${requested.toFixed(2)} - ${error.InvalidSupplyChange.reason}`,
    };
  }

  if ('LedgerError' in error) {
    return {
      title: 'Ledger Error',
      message: error.LedgerError,
    };
  }

  if ('Unauthorized' in error) {
    return { title: 'Unauthorized' };
  }

  if ('AlreadyInitialized' in error) {
    return { title: 'Already Initialized' };
  }

  if ('TokenNotApproved' in error) {
    return {
      title: 'Token Not Approved',
      message: `${error.TokenNotApproved.toText().slice(0, 10)}...`,
    };
  }

  if ('TokenAlreadyApproved' in error) {
    return {
      title: 'Token Already Approved',
      message: `${error.TokenAlreadyApproved.toText().slice(0, 10)}...`,
    };
  }

  if ('Other' in error) {
    return {
      title: `Error (${error.Other.code.toString()})`,
      message: error.Other.message,
    };
  }

  if ('TokenError' in error) {
    const token = error.TokenError.token.toText();
    return {
      title: 'Token Error',
      message: `${token.slice(0, 10)}... (code ${error.TokenError.code.toString()}): ${error.TokenError.message}`,
    };
  }

  // Fallback
  return {
    title: 'Unknown Error',
    message: safeStringify(error),
  };
}

// Log error details for debugging
export function logError(context: string, error: any) {
  console.group(`🔴 ${context}`);
  console.error('Raw error:', error);
  if (error && typeof error === 'object') {
    console.log('Error type:', Object.keys(error)[0]);
    console.log('Error details:', safeStringify(error));
  }
  console.groupEnd();
}

// Show user-friendly error message using toast
export function showError(context: string, error: any) {
  logError(context, error);

  if (error && typeof error === 'object' && !('message' in error)) {
    // It's a backend error
    const formatted = formatError(error as CommonError);
    showToast('error', formatted.title, formatted.message);
  } else if (error instanceof Error) {
    showToast('error', context, error.message);
  } else {
    showToast('error', context, 'Unknown error occurred');
  }
}

// Show success message
export function showSuccess(title: string, message?: string) {
  showToast('success', title, message);
}

// Show warning message
export function showWarning(title: string, message?: string) {
  showToast('warning', title, message);
}

// Show info message
export function showInfo(title: string, message?: string) {
  showToast('info', title, message);
}
