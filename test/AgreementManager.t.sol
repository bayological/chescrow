// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";
import { AgreementManager } from "contracts/AgreementManager.sol";
import { IAgreementManager } from "contracts/interfaces/IAgreementManager.sol";
import { TestERC20 } from "test/TestERC20.sol";

contract AgreementManagerTest is Test {
  AgreementManager internal testee;
  IAgreementManager.Agreement internal testAgreement;

  address private testServiceProvider;
  address private testClient;
  uint256 private testServiceProviderPK;
  uint256 private testClientPK;
  TestERC20 private testToken;

  function setUp() public virtual {
    // Setup test token
    testToken = new TestERC20();

    address[] memory paymentTokens = new address[](1);
    paymentTokens[0] = address(testToken);

    address initialOwner = address(this);
    testee = new AgreementManager(paymentTokens, initialOwner);

    // Setup test users
    (testServiceProvider, testServiceProviderPK) = makeAddrAndKey("serviceProvider");
    (testClient, testClientPK) = makeAddrAndKey("client");

    // Send client some test tokens
    testToken.transfer(testClient, 1000 ether);

    testAgreement = IAgreementManager.Agreement({
      id: 0,
      client: address(this),
      serviceProvider: address(this),
      deadline: block.timestamp,
      paymentToken: address(testToken),
      paymentAmount: 0,
      termsCID: "",
      termsDocumentHash: bytes32(0),
      creationTimestamp: block.timestamp,
      status: IAgreementManager.Status.DRAFT,
      serviceProviderSig: "",
      clientSig: ""
    });
  }

  /* ==================== Helper Functions ==================== */

  function createTestAgreement() internal {
    bytes32 termsDocumentHash = keccak256("fakeHashOfTermsDocument");

    // Setup agreement
    testAgreement.deadline = block.timestamp + 100;
    testAgreement.paymentAmount = 1 ether;
    testAgreement.client = testClient;
    testAgreement.termsDocumentHash = termsDocumentHash;

    // Get the signature
    bytes memory sig = getSignatureBytes(termsDocumentHash, testServiceProviderPK);

    // Add the provider signature
    testAgreement.serviceProviderSig = sig;

    // Switch to the service provider
    vm.prank(testServiceProvider);

    testee.createAgreement(testAgreement, sig);
  }

  function acceptTestAgreement() internal {
    // Get the client to sign the terms document hash
    bytes memory sig = getSignatureBytes(testAgreement.termsDocumentHash, testClientPK);

    // Switch to the client
    vm.startPrank(testClient);

    // Approve the payment amount
    testToken.approve(address(testee), testAgreement.paymentAmount);

    // Accept the agreement
    testee.acceptAgreement(1, sig);
  }

  function getSignatureBytes(bytes32 data, uint256 userPKey) internal pure returns (bytes memory sig) {
    // Prepend the Ethereum-specific message prefix
    bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", data));

    // Sign the Ethereum-specific message hash
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPKey, messageHash);

    // Combine v, r, and s into the full signature
    bytes memory signature = abi.encodePacked(r, s, v);

    // Return the combined signature
    return (signature);
  }

  /* ==================== Mutative Functions ==================== */

  /**
   * Create Agreement **********************
   */
  function test_createAgreement_whenDeadlineIsInPast_shouldRevert() external {
    // Set the block number to the future
    vm.roll(100);

    vm.expectRevert(IAgreementManager.DeadlineMustBeInFuture.selector);
    testee.createAgreement(testAgreement, "");
  }

  function test_createAgreement_whenPaymentTokenNotAccepted_shouldRevert() external {
    testAgreement.deadline = block.timestamp + 100;
    testAgreement.paymentToken = address(1);

    vm.expectRevert(IAgreementManager.PaymentTokenNotAccepted.selector);
    testee.createAgreement(testAgreement, "");
  }

  function test_createAgreement_whenPaymentAmountIsZero_shouldRevert() external {
    testAgreement.deadline = block.timestamp + 100;
    testAgreement.paymentAmount = 0;

    vm.expectRevert(IAgreementManager.PaymentAmountCannotBeZero.selector);
    testee.createAgreement(testAgreement, "");
  }

  function test_createAgreement_whenOferreeIsOferror_shouldRevert() external {
    testAgreement.deadline = block.timestamp + 100;
    testAgreement.paymentAmount = 1 ether;
    testAgreement.client = address(this);

    vm.expectRevert(IAgreementManager.ClientCannotBeServiceProvider.selector);
    testee.createAgreement(testAgreement, "");
  }

  function test_createAgreement_whenOferreeIsZero_shouldRevert() external {
    testAgreement.deadline = block.timestamp + 100;
    testAgreement.paymentAmount = 1 ether;
    testAgreement.client = address(0);

    vm.expectRevert(IAgreementManager.InvalidAddress.selector);
    testee.createAgreement(testAgreement, "");
  }

  function test_createAgreement_whenParamsAreValid_shouldEmit() external {
    vm.skip(false);

    (address serviceProvider, uint256 serviceProviderPK) = makeAddrAndKey("serviceProvider");
    vm.startPrank(serviceProvider);

    testAgreement.deadline = block.timestamp + 100;
    testAgreement.paymentAmount = 1 ether;
    testAgreement.client = makeAddr("client");
    testAgreement.termsDocumentHash = keccak256("fakeHashOfTermsDocument");

    // Prepend the Ethereum-specific message prefix
    bytes32 messageHash =
      keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", testAgreement.termsDocumentHash));

    // Sign the Ethereum-specific message hash
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(serviceProviderPK, messageHash);

    // Combine v, r, and s into the full signature
    bytes memory signature = abi.encodePacked(r, s, v);

    testAgreement.serviceProviderSig = signature;

    vm.expectEmit();
    emit IAgreementManager.AgreementCreated(
      1,
      testAgreement.client,
      serviceProvider,
      testAgreement.paymentToken,
      testAgreement.paymentAmount,
      testAgreement.deadline,
      testAgreement.termsCID,
      testAgreement.termsDocumentHash
    );

    testee.createAgreement(testAgreement, signature);
  }

  /**
   * Accept Agreement **********************
   */
  function test_acceptAgreement_whenAgreementNotFound_shouldRevert() external {
    vm.expectRevert(IAgreementManager.AgreementNotFound.selector);
    testee.acceptAgreement(123, "");
  }

  function test_acceptAgreement_whenAgreementInDraft_shouldEmitSuccess() external {
    //> Arrange

    // Get balances before
    uint256 clientBalanceBefore = testToken.balanceOf(testClient);
    uint256 agreementManagerBalanceBefore = testToken.balanceOf(address(testee));

    // Create an agreement from the service provider
    createTestAgreement();

    // Get the client to sign the terms document hash
    bytes memory sig = getSignatureBytes(testAgreement.termsDocumentHash, testClientPK);

    // Switch to the client
    vm.startPrank(testClient);

    // Approve the payment amount
    testToken.approve(address(testee), testAgreement.paymentAmount);

    //> Act
    vm.expectEmit();
    emit IAgreementManager.AgreementAccepted(1);
    testee.acceptAgreement(1, sig);

    //> Assert

    assertTrue(testToken.balanceOf(testClient) == clientBalanceBefore - testAgreement.paymentAmount);
    assertTrue(testToken.balanceOf(address(testee)) == agreementManagerBalanceBefore + testAgreement.paymentAmount);
    assertTrue(testee.getAgreement(1).status == IAgreementManager.Status.ACCEPTED);
  }

  function test_executeAgreement_whenAgreementIsAccepted_shouldEmitSuccess() external {
    //> Arrange

    // Set the payment token for the agreement
    testAgreement.paymentToken = address(testToken);
    createTestAgreement();
    acceptTestAgreement();

    //> Act
    vm.startPrank(testServiceProvider);
  }
}
