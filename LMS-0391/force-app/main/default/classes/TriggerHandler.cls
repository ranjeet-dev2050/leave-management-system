public virtual class TriggerHandler {

	public class TriggerHandlerException extends Exception {}

	protected List<SObject> oldRecords;
	protected List<SObject> newRecords;
	protected Map<Id, SObject> oldRecordsMap;

	/**
	* @return Ensure future calls are allowed an we have not reached the limit already
	*/
	public static Boolean isFutureAllowed() {
		return !System.isBatch() && !System.isQueueable() && !System.isFuture() && Limits.getFutureCalls() < Limits.getLimitFutureCalls();
	}

	public TriggerHandler() {
		this.oldRecords = Trigger.old;
		this.oldRecordsMap = Trigger.oldMap;
		this.newRecords = Trigger.new;
	}

	public TriggerHandler(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
		this.oldRecords = Trigger.old;
		this.newRecords = newRecords;
		this.oldRecordsMap = oldRecordsMap;
		run();
	}

	public void run() {
		try {
			if (Trigger.isBefore) {
				if (Trigger.isInsert) {
					beforeInsert();
				} 
				else if (Trigger.isUpdate) {
					beforeUpdate();
				} 
				else if (Trigger.isDelete) {
					beforeDelete();
				}
			} 
			else {
				if (Trigger.isInsert) {
					afterInsert();
				} 
				else if (Trigger.isUpdate) {
					afterUpdate();
				} 
				else if (Trigger.isDelete) {
					afterDelete();
				} 
				else if (Trigger.isUndelete) {
					afterUndelete();
				}
			}
			executeFinally();
		} 
		catch(Exception e) {
			System.debug('ERROR - '+ e.getMessage() + '! STACK_TRACE - ' + e.getStackTraceString());
			Boolean storedValue = Logger.usePlatFormEvent;
			Logger.usePlatFormEvent = true;
			Logger.handleInsertErrorLog(e, 'TriggerHandler', 'run', 'Error in TriggerHandler');
			Logger.usePlatFormEvent = storedValue;
			throw new TriggerHandlerException(e.getMessage());
		}
	}

	protected virtual void beforeInsert() {}
	protected virtual void beforeUpdate() {}
	protected virtual void beforeDelete() {}
	protected virtual void afterInsert() {}
	protected virtual void afterUpdate() {}
	protected virtual void afterDelete() {}
	protected virtual void afterUndelete() {}
	protected virtual void executeFinally() {}
}