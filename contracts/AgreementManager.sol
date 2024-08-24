// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.25;

import { IAgreementManager } from "./interfaces/IAgreementManager.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { console2 } from "forge-std/src/console2.sol";

/**
 * @notice  Allows the creation of an agreement between two parties to perform some service.
 *          One party must offer to enter into an agreement and the other must accept
 *          the terms of the agreement. Each agreement has two parties, serviceProvider and client.
 *          The serviceProvider first defines the terms of the offer, including token for payment
 *          and amount of token. Then the serviceProvider will add their signature and send the
 *          agreement to the client. The client can either accept or reject the agreement.
 *          If they accept, their signature is added to the agreement, the requested amount
 *          is deducted and transferred to the escrow contract along with the Agreement.
 */
contract AgreementManager is IAgreementManager, Ownable {
  using ECDSA for bytes32;
  using MessageHashUtils for bytes32;
  using SafeERC20 for IERC20;

  /* ==================== State Variables ==================== */

  mapping(uint256 => Agreement) public agreements;

  // Maps a token address to a boolean indicating if it is an allowed payment token
  mapping(address => bool) public isPaymentToken;

  // The next agreement ID to be used
  uint256 public nextId = 1;

  /* ==================== Constructor ==================== */

  constructor(address[] memory paymentTokens, address initialOwner) Ownable(initialOwner) {
    addPaymentTokens(paymentTokens);
  }

  /* ==================== View Functions ==================== */

  /**
   * @notice Retrieves an agreement by its ID.
   * @param agreementId The ID of the agreement to retrieve.
   * @return agreement The agreement object.
   */
  function getAgreement(uint256 agreementId) external view returns (Agreement memory agreement) {
    return agreements[agreementId];
  }

  /* ==================== Mutative Functions ==================== */

  /*********************** Agreements ***********************/

  /**
   * @notice Creates an agreement with the specified details.
   * @param agreement The Agreement struct containing all necessary details.
   * @param signature The signature of the service provider.
   * @return agreementId The ID of the created agreement.
   */
  function createAgreement(Agreement memory agreement, bytes memory signature) external returns (uint256 agreementId) {
    // Validate inputs
    if (agreement.deadline <= block.timestamp) revert DeadlineMustBeInFuture();
    if (!isPaymentToken[agreement.paymentToken]) revert PaymentTokenNotAccepted();
    if (agreement.paymentAmount == 0) revert PaymentAmountCannotBeZero();
    if (agreement.client == msg.sender) revert ClientCannotBeServiceProvider();
    if (agreement.client == address(0)) revert InvalidAddress();

    // Recover the service provider's address from the signature
    bytes32 ethMessageHash = agreement.termsDocumentHash.toEthSignedMessageHash();
    address recoveredAddress = ECDSA.recover(ethMessageHash, signature);
    if (recoveredAddress != msg.sender) revert InvalidSignature();

    // Generate a new agreement ID
    agreementId = nextId++;

    // Store the new agreement in the mapping
    agreements[agreementId] = Agreement({
      id: agreementId,
      client: agreement.client,
      serviceProvider: msg.sender,
      paymentToken: agreement.paymentToken,
      paymentAmount: agreement.paymentAmount,
      deadline: agreement.deadline,
      termsCID: agreement.termsCID,
      termsDocumentHash: agreement.termsDocumentHash,
      creationTimestamp: block.timestamp,
      status: Status.DRAFT,
      serviceProviderSig: agreement.serviceProviderSig,
      clientSig: ""
    });

    // Emit the AgreementCreated event with the updated parameters
    emit AgreementCreated(
      agreementId,
      agreement.client,
      msg.sender,
      agreement.paymentToken,
      agreement.paymentAmount,
      agreement.deadline,
      agreement.termsCID,
      agreement.termsDocumentHash
    );
  }

  /**
   * @notice Accepts an existing agreement.
   * @param agreementId The ID of the agreement to accept.
   * @param signature The signature of the client.
   */
  function acceptAgreement(uint256 agreementId, bytes memory signature) external {
    Agreement memory agreement = agreements[agreementId];
    if (agreement.id == 0) revert AgreementNotFound();
    if (agreement.status != Status.DRAFT) revert AgreementNotInDraft();
    if (msg.sender != agreement.client) revert SenderShouldBeParty();

    // Recover the client's address from the signature
    bytes32 ethMessageHash = agreement.termsDocumentHash.toEthSignedMessageHash();
    address recoveredAddress = ECDSA.recover(ethMessageHash, signature);
    if (recoveredAddress != msg.sender) revert InvalidSignature();

    IERC20 paymentToken = IERC20(agreement.paymentToken);
    uint256 paymentAmount = agreement.paymentAmount;

    if (paymentToken.balanceOf(msg.sender) < paymentAmount) revert InsufficientBalance();
    if (paymentToken.allowance(msg.sender, address(this)) < paymentAmount) revert InsufficientAllowance();

    // Update state
    agreements[agreementId].clientSig = signature;
    agreements[agreementId].status = Status.ACCEPTED;

    // do external calls
    paymentToken.safeTransferFrom(msg.sender, address(this), paymentAmount);

    emit AgreementAccepted(agreementId);
  }

  /**
   * @notice Sets agreement to execution state.
   * @param agreementId The ID of the agreement to execute.
   */
  function executeAgreement(uint256 agreementId) external returns (bool)
  {
    Agreement storage agreement = agreements[agreementId];
    if (agreement.id == 0) revert AgreementNotFound();
    if (agreement.status != Status.ACCEPTED) revert AgreementNotInDraft(); 
    if (msg.sender != agreement.serviceProvider) revert SenderShouldBeParty();

    agreement.status = Status.EXECUTION;
    emit AgreementInExecution(agreementId);
    return true;
  }

  /**
   * @notice Marks an agreement as completed.
   * @param agreementId The ID of the agreement to mark as completed.
   */
  function completeAgreement(uint256 agreementId) external {
    Agreement storage agreement = agreements[agreementId];
    if (agreement.id == 0) revert AgreementNotFound();
    if (agreement.status != Status.ACCEPTED) revert AgreementNotInDraft(); // Should probably add a different error message here
    if (msg.sender != agreement.serviceProvider && msg.sender != agreement.client) revert SenderShouldBeParty();

    agreement.status = Status.FULFILLED;

    emit AgreementCompleted(agreementId);
  }

  /*********************** Payment Tokens ***********************/

  /**
   * @notice Adds the specified payment tokens to the list of accepted payment tokens.
   * @param paymentTokens The payment tokens to add.
   */
  function addPaymentTokens(address[] memory paymentTokens) public onlyOwner {
    for (uint256 i = 0; i < paymentTokens.length; i++) {
      isPaymentToken[paymentTokens[i]] = true;
      emit PaymentTokenAdded(paymentTokens[i]);
    }
  }

  /**
   * @notice Removes the specified payment token from the list of accepted payment tokens.
   * @param paymentToken The payment token to remove.
   */
  function removePaymentToken(address paymentToken) public onlyOwner {
    isPaymentToken[paymentToken] = false;
  }
}
