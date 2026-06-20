public without sharing class Logger {

	private static final Integer MAX_ERROR_SMSG_LENGTH = Schema.SObjectType.Debug_Log__c.fields.Short_Message__c.getLength();
	private static final Integer MAX_ERROR_LMSG_LENGTH = Schema.SObjectType.Debug_Log__c.fields.Log_Message__c.getLength();
	private static final List<Debug_Log__c> Bulk_Logs = new List<Debug_Log__c>();
	private static final String LINE_BREAK_TEXT = '\n\n';
	/**
	 * Flag to indicate that Platform Events should be used by default
	 */
	public static Boolean usePlatFormEvent = false;

	/**
	 * Handles the insertion of Debug Log records from the Log platform events
	 * @param logEvents The list of Log Platform Events to be inserted
	 */
	public static void handleLogEvents(List<Log__e> logEvents) {
		// Make sure we are NOT going to use Platform Events again
		Logger.usePlatFormEvent = false;
		for (Log__e log : logEvents) {
			Bulk_Logs.add(
				(Debug_Log__c) JSON.deserialize(log.Serialized_Log__c, Debug_Log__c.class)
			);
		}
		handleSaveBulkLogs();
	}

	public static void handleSaveBulkLogs() {
		try {
			if (Bulk_Logs <> null && !Bulk_Logs.isEmpty()) {
				if (Logger.usePlatFormEvent) {
					List<Log__e> logEvents = new List<Log__e>();
					for (Debug_Log__c log : Bulk_Logs) {
						logEvents.add(new Log__e(Serialized_Log__c = JSON.serialize(log)));
					}
					EventBus.publish(logEvents);
				} 
				else {
					Database.insert(Bulk_Logs, Test.isRunningTest());
				}
				Bulk_Logs.clear();
			}
		} 
		catch (Exception e) {
			System.debug('ERROR - '+ e.getMessage() + '! STACK_TRACE - ' + e.getStackTraceString());
		}
	}

	/**
	 * @param logLevel The logging level
	 * @param sourceClass The source class where the error occurred
	 * @param sourceFunction The source function where the error occurred
	 * @param shortMessage The summary message
	 * @param referenceId The Id of the record the error occurred
	 * @param logMessage The detail log message
	 */
	public static Id handleInsertLog(
		LoggingLevel logLevel,
		String sourceClass, 
		String sourceFunction, 
		String shortMessage, 
		String referenceId, 
		String logMessage
	) {
		if (logLevel == null) {
			return null;
		}
		Debug_Log__c newLog = new Debug_Log__c();
		newLog.Short_Message__c = shortMessage;
		if (newLog.Short_Message__c <> null && newLog.Short_Message__c.length() > MAX_ERROR_SMSG_LENGTH) {
			newLog.Short_Message__c = shortMessage.substring(0, MAX_ERROR_SMSG_LENGTH);
		}
		newLog.Debug_Level__c = logLevel.name();
		newLog.Reference_ID__c = referenceId;
		newLog.Source_Class__c = sourceClass;
		newLog.Source_Function__c = sourceFunction;
		newLog.Log_Message__c = logMessage;
		if (newLog.Log_Message__c <> null && newLog.Log_Message__c.length() > MAX_ERROR_LMSG_LENGTH) {
			newLog.Log_Message__c = logMessage.substring(0, MAX_ERROR_LMSG_LENGTH);
		}
		newLog.OwnerId = UserInfo.getUserId();
		if (Logger.usePlatFormEvent) {
			EventBus.publish(new Log__e(Serialized_Log__c = JSON.serialize(newLog)));
		} 
		else {
			insert newLog;
			return newLog.Id;
		}
		return null;
	}

	/**
	 * @param Exception The exception occured
	 * @param sourceClass The source class where the error occurred
	 * @param sourceFunction The source function where the error occurred
	 * @param shortMessage The summary message
	 */
	public static Id handleInsertErrorLog(
		Exception e,
		String sourceClass, 
		String sourceFunction, 
		String shortMessage
	) {
		return handleInsertErrorLog(e, sourceClass, sourceFunction, shortMessage, null, null);
	}

	/**
	 * @param Exception The exception occured
	 * @param sourceClass The source class where the error occurred
	 * @param sourceFunction The source function where the error occurred
	 * @param shortMessage The summary message
	 * @param referenceId The Id of the record the error occurred
	 * @param logMessage The detail log message
	 */
	public static Id handleInsertErrorLog(
		Exception e,
		String sourceClass, 
		String sourceFunction, 
		String shortMessage, 
		String referenceId, 
		String logMessage
	) {
		List<String> errorInfo = new List<String>();
		errorInfo.add('ERROR_MESSAGE : ' + e.getMessage());
		errorInfo.add('STACK_TRACE : ' + e.getStackTraceString());
		String errorMessage = String.join(errorInfo, LINE_BREAK_TEXT);
		if (logMessage == null) {
			logMessage = '';
		}
		logMessage = errorMessage + LINE_BREAK_TEXT + logMessage;
		if (shortMessage == null) {
			shortMessage = 'ERROR OCCURED';
		}
		return handleInsertLog(LoggingLevel.ERROR, sourceClass, sourceFunction, shortMessage, referenceId, logMessage);
	}
}