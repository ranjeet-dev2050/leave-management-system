@isTest
private class LoggerTest {

	// ─────────────────────────────────────────────────────────────────
	// Test Data / Helper
	// ─────────────────────────────────────────────────────────────────

	private static final String SOURCE_CLASS    = 'TestClass';
	private static final String SOURCE_FUNCTION = 'testMethod';
	private static final String SHORT_MSG       = 'Short test message';
	private static final String LOG_MSG         = 'Detailed log message for testing';
	private static final String REF_ID          = 'REF-001';

	/** Returns a simple runtime exception for error-log tests. */
	private static Exception makeException() {
		try {
			Integer x = Integer.valueOf('not-a-number');
			return null; // never reached
		} catch (Exception e) {
			return e;
		}
	}


	// ─────────────────────────────────────────────────────────────────
	// handleInsertLog — Direct DB path
	// ─────────────────────────────────────────────────────────────────

	@isTest
	static void testHandleInsertLog_DirectInsert_Success() {
		Logger.usePlatFormEvent = false;

		Test.startTest();
		Id logId = Logger.handleInsertLog(
			LoggingLevel.INFO,
			SOURCE_CLASS,
			SOURCE_FUNCTION,
			SHORT_MSG,
			REF_ID,
			LOG_MSG
		);
		Test.stopTest();

		Assert.isNotNull(logId, 'Expected a non-null record Id from direct insert');

		Debug_Log__c inserted = [
			SELECT Short_Message__c, Debug_Level__c, Source_Class__c,
					Source_Function__c, Reference_ID__c, Log_Message__c
			FROM   Debug_Log__c
			WHERE  Id = :logId
		];

		Assert.areEqual(SHORT_MSG,       inserted.Short_Message__c);
		Assert.areEqual('INFO',          inserted.Debug_Level__c);
		Assert.areEqual(SOURCE_CLASS,    inserted.Source_Class__c);
		Assert.areEqual(SOURCE_FUNCTION, inserted.Source_Function__c);
		Assert.areEqual(REF_ID,          inserted.Reference_ID__c);
		Assert.areEqual(LOG_MSG,         inserted.Log_Message__c);
	}

	@isTest
	static void testHandleInsertLog_NullLogLevel_ReturnsNull() {
		Logger.usePlatFormEvent = false;

		Test.startTest();
		Id logId = Logger.handleInsertLog(
			null,
			SOURCE_CLASS,
			SOURCE_FUNCTION,
			SHORT_MSG,
			REF_ID,
			LOG_MSG
		);
		Test.stopTest();

		Assert.isNull(logId, 'Null log level should return null without inserting');
		Assert.areEqual(0, [SELECT COUNT() FROM Debug_Log__c], 'No records should be inserted');
	}

	@isTest
	static void testHandleInsertLog_ShortMessage_Truncated() {
		Logger.usePlatFormEvent = false;

		Integer maxLen = Schema.SObjectType.Debug_Log__c.fields.Short_Message__c.getLength();
		String longShortMsg = 'A'.repeat(maxLen + 50);

		Test.startTest();
		Id logId = Logger.handleInsertLog(
			LoggingLevel.WARN,
			SOURCE_CLASS,
			SOURCE_FUNCTION,
			longShortMsg,
			null,
			LOG_MSG
		);
		Test.stopTest();

		Assert.isNotNull(logId);
		Debug_Log__c inserted = [SELECT Short_Message__c FROM Debug_Log__c WHERE Id = :logId];
		Assert.areEqual(maxLen, inserted.Short_Message__c.length(),
			'Short_Message__c should be truncated to field max length');
	}

	@isTest
	static void testHandleInsertLog_LogMessage_Truncated() {
		Logger.usePlatFormEvent = false;

		Integer maxLen = Schema.SObjectType.Debug_Log__c.fields.Log_Message__c.getLength();
		String longLogMsg = 'B'.repeat(maxLen + 100);

		Test.startTest();
		Id logId = Logger.handleInsertLog(
			LoggingLevel.ERROR,
			SOURCE_CLASS,
			SOURCE_FUNCTION,
			SHORT_MSG,
			null,
			longLogMsg
		);
		Test.stopTest();

		Assert.isNotNull(logId);
		Debug_Log__c inserted = [SELECT Log_Message__c FROM Debug_Log__c WHERE Id = :logId];
		Assert.areEqual(maxLen, inserted.Log_Message__c.length(),
			'Log_Message__c should be truncated to field max length');
	}

	@isTest
	static void testHandleInsertLog_NullMessages_NoTruncationError() {
		Logger.usePlatFormEvent = false;

		Test.startTest();
		Id logId = Logger.handleInsertLog(
			LoggingLevel.DEBUG,
			SOURCE_CLASS,
			SOURCE_FUNCTION,
			null,   // null shortMessage
			null,
			null    // null logMessage
		);
		Test.stopTest();

		// Should succeed without any NPE from the truncation guards
		Assert.isNotNull(logId);
	}

	@isTest
	static void testHandleInsertLog_AllLoggingLevels() {
		Logger.usePlatFormEvent = false;

		List<LoggingLevel> levels = new List<LoggingLevel>{
			LoggingLevel.ERROR,
			LoggingLevel.WARN,
			LoggingLevel.INFO,
			LoggingLevel.DEBUG
		};

		Test.startTest();
		for (LoggingLevel lvl : levels) {
			Id logId = Logger.handleInsertLog(
				lvl, SOURCE_CLASS, SOURCE_FUNCTION, SHORT_MSG, null, LOG_MSG
			);
			Assert.isNotNull(logId, 'Expected Id for level: ' + lvl);
		}
		Test.stopTest();

		Assert.areEqual(levels.size(), [SELECT COUNT() FROM Debug_Log__c]);
	}


	// ─────────────────────────────────────────────────────────────────
	// handleInsertLog — Platform Event path
	// ─────────────────────────────────────────────────────────────────

	@isTest
	static void testHandleInsertLog_PlatformEvent_ReturnsNull() {
		Logger.usePlatFormEvent = true;

		Test.startTest();
		Id logId = Logger.handleInsertLog(
			LoggingLevel.INFO,
			SOURCE_CLASS,
			SOURCE_FUNCTION,
			SHORT_MSG,
			REF_ID,
			LOG_MSG
		);
		Test.stopTest();

		// Platform event path should return null (no DML Id)
		Assert.isNull(logId, 'Platform event path should return null');
		Logger.usePlatFormEvent = false; // reset
	}


	// ─────────────────────────────────────────────────────────────────
	// handleInsertErrorLog — 4-param overload
	// ─────────────────────────────────────────────────────────────────

	@isTest
	static void testHandleInsertErrorLog_FourParam_Success() {
		Logger.usePlatFormEvent = false;
		Exception ex = makeException();

		Test.startTest();
		Id logId = Logger.handleInsertErrorLog(ex, SOURCE_CLASS, SOURCE_FUNCTION, SHORT_MSG);
		Test.stopTest();

		Assert.isNotNull(logId);

		Debug_Log__c inserted = [
			SELECT Debug_Level__c, Short_Message__c, Log_Message__c
			FROM   Debug_Log__c
			WHERE  Id = :logId
		];

		Assert.areEqual('ERROR', inserted.Debug_Level__c);
		Assert.areEqual(SHORT_MSG, inserted.Short_Message__c);
		Assert.isTrue(inserted.Log_Message__c.contains('ERROR_MESSAGE'),
			'Log message should contain ERROR_MESSAGE label');
		Assert.isTrue(inserted.Log_Message__c.contains('STACK_TRACE'),
			'Log message should contain STACK_TRACE label');
	}

	@isTest
	static void testHandleInsertErrorLog_FourParam_NullShortMessage_UsesDefault() {
		Logger.usePlatFormEvent = false;
		Exception ex = makeException();

		Test.startTest();
		Id logId = Logger.handleInsertErrorLog(ex, SOURCE_CLASS, SOURCE_FUNCTION, null);
		Test.stopTest();

		Assert.isNotNull(logId);
		Debug_Log__c inserted = [SELECT Short_Message__c FROM Debug_Log__c WHERE Id = :logId];
		Assert.areEqual('ERROR OCCURED', inserted.Short_Message__c,
			'Null shortMessage should default to "ERROR OCCURED"');
	}


	// ─────────────────────────────────────────────────────────────────
	// handleInsertErrorLog — 6-param overload
	// ─────────────────────────────────────────────────────────────────

	@isTest
	static void testHandleInsertErrorLog_SixParam_Success() {
		Logger.usePlatFormEvent = false;
		Exception ex = makeException();

		Test.startTest();
		Id logId = Logger.handleInsertErrorLog(
			ex, SOURCE_CLASS, SOURCE_FUNCTION, SHORT_MSG, REF_ID, LOG_MSG
		);
		Test.stopTest();

		Assert.isNotNull(logId);

		Debug_Log__c inserted = [
			SELECT Debug_Level__c, Reference_ID__c, Log_Message__c, Short_Message__c
			FROM   Debug_Log__c
			WHERE  Id = :logId
		];

		Assert.areEqual('ERROR',   inserted.Debug_Level__c);
		Assert.areEqual(REF_ID,    inserted.Reference_ID__c);
		Assert.areEqual(SHORT_MSG, inserted.Short_Message__c);
		// Combined log should contain both exception info and the custom log message
		Assert.isTrue(inserted.Log_Message__c.contains('ERROR_MESSAGE'));
		Assert.isTrue(inserted.Log_Message__c.contains(LOG_MSG),
			'Custom logMessage should be appended');
	}

	@isTest
	static void testHandleInsertErrorLog_SixParam_NullLogMessage_NoNPE() {
		Logger.usePlatFormEvent = false;
		Exception ex = makeException();

		Test.startTest();
		Id logId = Logger.handleInsertErrorLog(
			ex, SOURCE_CLASS, SOURCE_FUNCTION, SHORT_MSG, REF_ID, null
		);
		Test.stopTest();

		// Null logMessage should be treated as empty string without NPE
		Assert.isNotNull(logId);
		Debug_Log__c inserted = [SELECT Log_Message__c FROM Debug_Log__c WHERE Id = :logId];
		Assert.isTrue(inserted.Log_Message__c.contains('ERROR_MESSAGE'));
	}


	// ─────────────────────────────────────────────────────────────────
	// handleSaveBulkLogs — Direct DB path
	// ─────────────────────────────────────────────────────────────────

	@isTest
	static void testHandleSaveBulkLogs_DirectInsert() {
		Logger.usePlatFormEvent = false;

		// Simulate two log events being handled (populates Bulk_Logs via handleLogEvents)
		List<Log__e> events = new List<Log__e>();
		for (Integer i = 0; i < 3; i++) {
			Debug_Log__c log = new Debug_Log__c(
				Short_Message__c  = 'Bulk msg ' + i,
				Debug_Level__c    = 'INFO',
				Source_Class__c   = SOURCE_CLASS,
				Source_Function__c = SOURCE_FUNCTION,
				Log_Message__c    = 'Bulk detail ' + i
			);
			events.add(new Log__e(Serialized_Log__c = JSON.serialize(log)));
		}

		Test.startTest();
		Logger.handleLogEvents(events);
		Test.stopTest();

		Assert.areEqual(3, [SELECT COUNT() FROM Debug_Log__c],
			'3 bulk log records should be inserted');
	}

	@isTest
	static void testHandleSaveBulkLogs_EmptyList_NoInsert() {
		Logger.usePlatFormEvent = false;

		Test.startTest();
		Logger.handleSaveBulkLogs(); // called with empty Bulk_Logs
		Test.stopTest();

		Assert.areEqual(0, [SELECT COUNT() FROM Debug_Log__c],
			'No records should be inserted when bulk list is empty');
	}


	// ─────────────────────────────────────────────────────────────────
	// handleLogEvents — resets usePlatFormEvent flag
	// ─────────────────────────────────────────────────────────────────

	@isTest
	static void testHandleLogEvents_ResetsPlatformEventFlag() {
		Logger.usePlatFormEvent = true; // pre-set to true

		Debug_Log__c log = new Debug_Log__c(
			Short_Message__c   = 'Event reset test',
			Debug_Level__c     = 'DEBUG',
			Source_Class__c    = SOURCE_CLASS,
			Source_Function__c = SOURCE_FUNCTION
		);
		List<Log__e> events = new List<Log__e>{
			new Log__e(Serialized_Log__c = JSON.serialize(log))
		};

		Test.startTest();
		Logger.handleLogEvents(events);
		Test.stopTest();

		Assert.isFalse(Logger.usePlatFormEvent,
			'handleLogEvents should reset usePlatFormEvent to false');
	}


	// ─────────────────────────────────────────────────────────────────
	// OwnerId is set to running user
	// ─────────────────────────────────────────────────────────────────

	@isTest
	static void testHandleInsertLog_OwnerIdSetToCurrentUser() {
		Logger.usePlatFormEvent = false;

		Test.startTest();
		Id logId = Logger.handleInsertLog(
			LoggingLevel.INFO, SOURCE_CLASS, SOURCE_FUNCTION, SHORT_MSG, null, null
		);
		Test.stopTest();

		Debug_Log__c inserted = [SELECT OwnerId FROM Debug_Log__c WHERE Id = :logId];
		Assert.areEqual(UserInfo.getUserId(), inserted.OwnerId,
			'OwnerId should be set to the running user');
	}
}