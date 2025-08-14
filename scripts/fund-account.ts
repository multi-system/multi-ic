import { Principal } from '@dfinity/principal';
import { minter } from '../src/tests/e2e/identity';
import { tokenA, tokenB, tokenC } from '../src/tests/e2e/actor';

async function fundPrincipalWithTokens(
  targetPrincipal: Principal,
  amountPerToken: bigint = BigInt(10000000000000) // 100,000 tokens default
): Promise<{ success: boolean; results: string[] }> {
  const results: string[] = [];

  try {
    console.log(
      `Funding ${targetPrincipal.toText()} with ${Number(amountPerToken) / 1e8} tokens each...`
    );

    // Create actor instances
    const tokenAInstance = await tokenA(minter);
    const tokenBInstance = await tokenB(minter);
    const tokenCInstance = await tokenC(minter);

    const transfers = await Promise.all([
      tokenAInstance
        .icrc1_transfer({
          to: { owner: targetPrincipal, subaccount: [] },
          amount: amountPerToken,
          fee: [],
          memo: [],
          from_subaccount: [],
          created_at_time: [],
        })
        .catch((err) => ({ err })),

      tokenBInstance
        .icrc1_transfer({
          to: { owner: targetPrincipal, subaccount: [] },
          amount: amountPerToken,
          fee: [],
          memo: [],
          from_subaccount: [],
          created_at_time: [],
        })
        .catch((err) => ({ err })),

      tokenCInstance
        .icrc1_transfer({
          to: { owner: targetPrincipal, subaccount: [] },
          amount: amountPerToken,
          fee: [],
          memo: [],
          from_subaccount: [],
          created_at_time: [],
        })
        .catch((err) => ({ err })),
    ]);

    let successCount = 0;
    transfers.forEach((result, index) => {
      const tokenName = ['Token A', 'Token B', 'Token C'][index];
      if ('ok' in result || (result as any).Ok) {
        results.push(`✅ ${tokenName}: Success`);
        successCount++;
      } else {
        results.push(`❌ ${tokenName}: Failed`);
      }
    });

    return { success: successCount === 3, results };
  } catch (error) {
    return { success: false, results: [`Error: ${error}`] };
  }
}

async function main() {
  const principalText = process.argv[2];
  const amount = process.argv[3];

  if (!principalText) {
    console.log('\n💰 Fund Internet Identity Account');
    console.log('==================================');
    console.log('\nUsage:');
    console.log('  yarn fund <principal>           # Funds with 100,000 tokens each');
    console.log('  yarn fund <principal> <amount>  # Funds with custom amount');
    console.log('\nExample:');
    console.log('  yarn fund j5b9r-zw4cn-o7aie-hzt4e-fqkwu-jqzwl-5v5k3-weq2x-gszp2-py6p6-fae');
    console.log(
      '  yarn fund j5b9r-zw4cn-o7aie-hzt4e-fqkwu-jqzwl-5v5k3-weq2x-gszp2-py6p6-fae 50000'
    );
    process.exit(0);
  }

  try {
    const targetPrincipal = Principal.fromText(principalText);
    const fundAmount = amount
      ? BigInt(Math.floor(parseFloat(amount) * 100000000))
      : BigInt(10000000000000); // Default 100,000 tokens

    const result = await fundPrincipalWithTokens(targetPrincipal, fundAmount);

    result.results.forEach((r) => console.log(r));

    if (result.success) {
      console.log(`\n✅ Successfully funded ${principalText}`);
    } else {
      console.log('\n⚠️  Some transfers failed');
    }
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

main();
