public without sharing class AbsenceTriggerHandler extends TriggerHandler {

	public class AbsenceTriggerHandlerException extends Exception {}

	@TestVisible private static final String NO_MANAGER_ERROR = 'Manager details not found, please contact admin.';

	public AbsenceTriggerHandler(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
		super(newRecords, oldRecordsMap);
	}

	public override void beforeInsert() {
		this.handleFieldPopulationOnInsert();
		this.handleTotalDaysCount();
	}

	public override void beforeUpdate() {
		this.handleTotalDaysCount();
	}

	/**
	 * @name : handleFieldPopulationOnInsert
	 * @param : none
	 * @return : none
	 * @description : This method handles field population on insertion.
	 */
	@TestVisible private void handleFieldPopulationOnInsert() {
		List<Absence__c> absenceList = (List<Absence__c>) this.newRecords;
		User currentUser = UserData.getCurrentUserData();
		if (currentUser.ManagerId == null) {
			absenceList[0].addError(NO_MANAGER_ERROR);
			return;
		}
		for (Absence__c ab : absenceList) {
			ab.Requester__c = currentUser.Id;
			ab.Approver__c = currentUser.ManagerId;
			ab.Status__c = 'Draft';
		}
	}

	/**
	 * @name : handleTotalDaysCount
	 * @param : none
	 * @return : none
	 * @description : This method handles calculation of Total Days using default business hours.
	 */
	@TestVisible private void handleTotalDaysCount() {
		List<Absence__c> absenceList = (List<Absence__c>) this.newRecords;
		List<BusinessHours> businessHrs = BusinessHoursUtil.getDefaultBusinessHour();
		for (Absence__c ab : absenceList) {
			if (ab.Start_Date__c == null || ab.End_Date__c == null) {
				continue; // Validation rule will handle redquired error
			}
			DateTime startTime = DateTime.newInstance(ab.Start_Date__c, Time.newInstance(0, 0, 0, 0));
			DateTime endTime = DateTime.newInstance(ab.End_Date__c.addDays(1), Time.newInstance(0, 0, 0, 0));
			Long msDuration = BusinessHours.diff(businessHrs[0].Id, startTime, endTime);
			Integer totalDays = Integer.valueOf(((msDuration/1000)/(3600))/24);
			ab.Total_Days__c = totalDays;
		}
	}
}