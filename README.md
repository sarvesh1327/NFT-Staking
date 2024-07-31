## NFT Staking

**This protocol allows users to stake their NFT in returns of a reward in terms of a ERC20 tokens**

### Initiation of the Repo
1. Install all the dependencies
    ```shell
    forge install --no-commit
    ```

2. Complie the contracts

    ```shell
    forge build
    ```

### Deploy contracts
   ```shell
   make deploy
   ```

### Testing
```shell
make test
```
### Interaction
1. Stake NFT
   ```javascript
   staking.stake(tokenId)
   ```
2. Unstake NFT
   ```javascript
   staking.unstake(tokenId)
   ```
3. Withdraw NFT
    ```javascript
   staking.withdraw(tokenId)
   ```

4. Claim Rewards
    ```javascript
   staking.claim()
   ```
