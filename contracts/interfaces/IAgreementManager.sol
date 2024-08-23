// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.25;

interface IAgreementManager {
  struct Agreement {
    uint256 id;
    address client;
    address serviceProvider;
    uint256 deadline;
    address paymentToken;
    uint256 paymentAmount;
    string termsCID;
    bytes32 termsDocumentHash;
    uint256 creationTimestamp;
    Status status;
    bytes serviceProviderSig;
    bytes clientSig;
  }

  enum Status {
    DRAFT,
    ACCEPTED,
    EXECUTION,
    FULFILLED,
    DISPUTE,
    CLOSED
  }

  error DeadlineMustBeInFuture();
  error PaymentAmountCannotBeZero();
  error ClientCannotBeServiceProvider();
  error PaymentTokenNotAccepted();
  error AgreementNotFound();
  error Unauthorized();
  error AgreementNotInDraft();
  error AgreementAlreadyCompleted();
  error InvalidSignature();
  error SenderShouldBeParty();
  error InvalidAddress();
  error InsufficientPaymentToken();

  /**
   * @notice Emitted when a new agreement is created.
   * @param agreementId The ID of the created agreement.
   * @param client The address of the party receiving the offer.
   * @param serviceProvider The address of the service provider (offering party).
   * @param paymentToken The address of the token to be used for payment.
   * @param paymentAmount The amount of the payment token required.
   * @param deadline The deadline for the completion of the service.
   * @param termsCID The IPFS CID of the agreement terms document.
   * @param termsDocumentHash The hash of the agreement terms document.
   */
  event AgreementCreated(
    uint256 agreementId,
    address client,
    address serviceProvider,
    address paymentToken,
    uint256 paymentAmount,
    uint256 deadline,
    string termsCID,
    bytes32 termsDocumentHash
  );

  /**
   * @notice Emitted when an agreement is accepted.
   * @param agreementId The ID of the accepted agreement.
   */
  event AgreementAccepted(uint256 agreementId);

  /**
   * @notice Emitted when an agreement is completed.
   * @param agreementId The ID of the completed agreement.
   */
  event AgreementCompleted(uint256 agreementId);

  /**
   * @notice Creates an agreement with the specified details.
   * @param agreement The Agreement struct containing all necessary details.
   * @param signature The signature of the service provider.
   * @return agreementId The ID of the created agreement.
   */
  function createAgreement(Agreement memory agreement, bytes memory signature) external returns (uint256 agreementId);

  /**
   * @notice Retrieves an agreement by its ID.
   * @param agreementId The ID of the agreement to retrieve.
   * @return agreement The agreement details.
   */
  function getAgreement(uint256 agreementId) external view returns (Agreement memory agreement);

  /**
   * @notice Accepts an existing agreement.
   * @param agreementId The ID of the agreement to accept.
   * @param signature Terms hash signed by client.
   */
  function acceptAgreement(uint256 agreementId, bytes memory signature) external;

  /**
   * @notice Marks an agreement as completed.
   * @param agreementId The ID of the agreement to mark as completed.
   */
  function completeAgreement(uint256 agreementId) external;

  // TODO: Add functions for other states (e.g. dispute, execution)
}
