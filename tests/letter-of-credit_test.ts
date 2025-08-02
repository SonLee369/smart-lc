import { describe, expect, it } from 'vitest';
import { Cl, cvToValue, uintCV, principalCV, asciiCV, boolCV, tupleCV } from '@stacks/transactions';
import { Clarinet } from '@stacks/clarinet-sdk';

describe("Letter of Credit contract tests", () => {
  it("allows the contract owner to authorize a bank, which can then create a letter of credit", async () => {
    // Arrange: Get the Clarinet context
    const clarinet = await Clarinet.create();
    const accounts = clarinet.getAccounts();
    const deployer = accounts.get('deployer')!;
    const bank1 = accounts.get('wallet_1')!; // Issuing bank
    const bank2 = accounts.get('wallet_2')!; // Advising bank
    const importer = accounts.get('wallet_3')!;
    const exporter = accounts.get('wallet_4')!;

    // Action 1: Authorize bank1. This must be called by the deployer.
    const addBankTx = await clarinet.call(
        'letter-of-credit',
        'add-authorized-bank',
        [principalCV(bank1.address)],
        deployer.address
    );

    // Assert 1: The transaction should be successful (returns (ok true))
    expect(addBankTx.result).toBeOk(Cl.bool(true));

    // Action 2: Now that bank1 is authorized, it can create a letter of credit.
    const createLcTx = await clarinet.call(
        'letter-of-credit',
        'create-letter-of-credit',
        [
            principalCV(bank1.address),      // issuing-bank
            principalCV(bank2.address),      // advising-bank
            principalCV(importer.address),   // importer
            principalCV(exporter.address),   // exporter
            uintCV(1000000),                 // amount
            asciiCV("USD"),                  // currency
            uintCV(100),                     // expiry-date (at block 100)
            tupleCV({ // documents
                'commercial-invoice': boolCV(true),
                'bill-of-lading': boolCV(true),
                'packing-list': boolCV(true),
                'certificate-of-origin': boolCV(false),
                'insurance-certificate': boolCV(true),
                'inspection-certificate': boolCV(false),
            }),
        ],
        bank1.address // The call is made by the newly authorized bank
    );

    // Assert 2: The creation should be successful and return the new LC ID (which is 1)
    expect(createLcTx.result).toBeOk(Cl.uint(1));

    // Optional: You can also read data directly from the contract's data maps
    const lcCounter = await clarinet.read(
        'letter-of-credit',
        'get-lc-counter',
        [],
        deployer.address
    );
    expect(lcCounter.result).toBeOk(Cl.uint(1));
  });
});