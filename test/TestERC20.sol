// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
  constructor() ERC20("Test Token", "TT") {
    _mint(msg.sender, 1000000 * 10 ** uint(decimals()));
  }
}
