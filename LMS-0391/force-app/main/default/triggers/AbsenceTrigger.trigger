trigger AbsenceTrigger on Absence__c (before insert, after insert, before update, after update) {
	new AbsenceTriggerHandler(Trigger.new, Trigger.oldMap);
}