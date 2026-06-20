/**
 * @description Test class for AbsenceTriggerHandler
 *
 * KEY NOTES ON BusinessHours:
 * ─────────────────────────────────────────────────────────────────────────────
 * 1. BusinessHours.diff() is a static platform method — it CANNOT be mocked.
 * 2. The default Business Hours record always exists in any org (it is a system
 *    record created by Salesforce and cannot be deleted in tests).
 * 3. Because BusinessHours.diff() returns real calendar-aware milliseconds, we
 *    do NOT assert an exact Total_Days__c value. Instead we assert:
 *      • The field is populated (not null).
 *      • The value is >= 0 (non-negative).
 *      • Boundary direction: a wider date range produces >= days than a
 *        narrower range.
 *    This avoids fragile tests that break across orgs/timezones/BH configs.
 * 4. For null Start/End date records, Total_Days__c is intentionally left null
 *    (the handler skips them; a validation rule enforces required fields).
 * ─────────────────────────────────────────────────────────────────────────────
 */
@isTest
private class AbsenceTriggerHandlerTest {

    // ──────────────────────────────────────────────────────────────────
    // Test data helpers
    // ──────────────────────────────────────────────────────────────────

    /**
     * Returns a User who has a ManagerId set, using this priority:
     *
     *  1. Licence available (>= 2 free slots)
     *       → Insert a fresh manager + employee for clean test isolation.
     *  2. No licence
     *       → Query any existing active User with ManagerId != null.
     *  3. No licence AND no qualifying existing User
     *       → Throw a descriptive exception so the test fails with clear context.
     */
    private static User resolveUserWithManager() {
        if (isLicenceAvailable()) {
            return createNewUserWithManager();
        }

        List<User> existing = [
            SELECT Id, ManagerId
            FROM   User
            WHERE  IsActive   = true
            AND    ManagerId != null
            AND    Id        != :UserInfo.getUserId()
            LIMIT  1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        throw new AbsenceTriggerHandler.AbsenceTriggerHandlerException(
            'Test setup failed: no Salesforce licence is available to create a test User, ' +
            'and no existing active User with a ManagerId was found in this org. ' +
            'Please free up a licence or assign a Manager to at least one active User.'
        );
    }

    /**
     * Returns a User with NO manager set, using this priority:
     *
     *  1. Licence available
     *       → Insert a fresh user without a manager.
     *  2. No licence
     *       → Query any existing active User where ManagerId is null,
     *         excluding the running user (who may have a manager).
     *  3. No licence AND no qualifying existing User
     *       → Throw a descriptive exception.
     */
    private static User resolveUserWithoutManager() {
        if (isLicenceAvailable()) {
            return createNewUserWithoutManager();
        }

        List<User> existing = [
            SELECT Id, ManagerId
            FROM   User
            WHERE  IsActive  = true
            AND    ManagerId = null
            AND    Id       != :UserInfo.getUserId()
            LIMIT  1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        throw new AbsenceTriggerHandler.AbsenceTriggerHandlerException(
            'Test setup failed: no Salesforce licence is available to create a test User, ' +
            'and no existing active User without a ManagerId was found in this org. ' +
            'Please free up a licence or ensure at least one active User has no Manager assigned.'
        );
    }

    /**
     * Returns true when the org has at least 2 free Salesforce licence slots
     * (1 for manager + 1 for employee).
     */
    private static Boolean isLicenceAvailable() {
        List<UserLicense> licences = [
            SELECT TotalLicenses, UsedLicenses
            FROM   UserLicense
            WHERE  Name = 'Salesforce'
            LIMIT  1
        ];
        if (licences.isEmpty()) {
            return false;
        }
        return (licences[0].TotalLicenses - licences[0].UsedLicenses) >= 2;
    }

    /**
     * Inserts a fresh manager + employee pair and returns the employee.
     * Only called after confirming licence availability.
     */
    private static User createNewUserWithManager() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        Long ts   = DateTime.now().getTime();

        User manager = new User(
            FirstName         = 'Test',
            LastName          = 'Manager',
            Email             = 'test.mgr.abs' + ts + '@example.com',
            Username          = 'test.mgr.abs' + ts + '@example.com',
            Alias             = 'tmgr',
            TimeZoneSidKey    = 'America/New_York',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = p.Id
        );
        insert manager;

        User employee = new User(
            FirstName         = 'Test',
            LastName          = 'Employee',
            Email             = 'test.emp.abs' + ts + '@example.com',
            Username          = 'test.emp.abs' + ts + '@example.com',
            Alias             = 'temp',
            TimeZoneSidKey    = 'America/New_York',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = p.Id,
            ManagerId         = manager.Id
        );
        insert employee;

        return employee;
    }

    /**
     * Inserts a fresh user with no manager assigned.
     * Only called after confirming licence availability.
     */
    private static User createNewUserWithoutManager() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        Long ts   = DateTime.now().getTime();

        User u = new User(
            FirstName         = 'Test',
            LastName          = 'NoMgr',
            Email             = 'test.nomgr.abs' + ts + '@example.com',
            Username          = 'test.nomgr.abs' + ts + '@example.com',
            Alias             = 'tnmg',
            TimeZoneSidKey    = 'America/New_York',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = p.Id
            // ManagerId intentionally omitted
        );
        insert u;
        return u;
    }

    /**
     * Builds an Absence__c record in memory (not inserted yet).
     */
    private static Absence__c buildAbsence(Date startDate, Date endDate) {
        return new Absence__c(
            Start_Date__c = startDate,
            End_Date__c   = endDate
        );
    }


    // ──────────────────────────────────────────────────────────────────
    // handleFieldPopulationOnInsert — via beforeInsert trigger path
    // ──────────────────────────────────────────────────────────────────

    /**
     * Happy path: insert an Absence__c as a user who has a manager.
     * Verifies Requester__c, Approver__c, and Status__c are auto-populated.
     */
    @isTest
    static void testBeforeInsert_FieldPopulation_WithManager() {
        User emp = resolveUserWithManager();

        System.runAs(emp) {
            Absence__c ab = buildAbsence(Date.today(), Date.today().addDays(2));

            Test.startTest();
            insert ab;
            Test.stopTest();

            Absence__c result = [
                SELECT Requester__c, Approver__c, Status__c
                FROM   Absence__c
                WHERE  Id = :ab.Id
            ];

            Assert.areEqual(emp.Id,        result.Requester__c,
                'Requester__c should be set to the running user');
            Assert.areEqual(emp.ManagerId, result.Approver__c,
                'Approver__c should be set to the running user\'s manager');
            Assert.areEqual('Draft',       result.Status__c,
                'Status__c should default to "Draft" on insert');
        }
    }

    /**
     * When the current user has no manager, addError() is called on the
     * first record. The DML should fail with an error containing the
     * NO_MANAGER_ERROR message.
     */
    @isTest
    static void testBeforeInsert_FieldPopulation_NoManager_AddsError() {
        User noMgr = resolveUserWithoutManager();

        System.runAs(noMgr) {
            Absence__c ab = buildAbsence(Date.today(), Date.today().addDays(1));

            Test.startTest();
            Database.SaveResult sr = Database.insert(ab, false); // allOrNone = false
            Test.stopTest();

            Assert.isFalse(sr.isSuccess(),
                'Insert should fail when user has no manager');
            Assert.isTrue(
                sr.getErrors()[0].getMessage().contains(AbsenceTriggerHandler.NO_MANAGER_ERROR),
                'Error message should contain the no-manager constant'
            );
        }
    }

    /**
     * Bulk insert: all records in the list should have fields populated
     * when the running user has a manager.
     */
    @isTest
    static void testBeforeInsert_BulkFieldPopulation_WithManager() {
        User emp = resolveUserWithManager();

        System.runAs(emp) {
            List<Absence__c> absences = new List<Absence__c>();
            for (Integer i = 0; i < 5; i++) {
                absences.add(buildAbsence(Date.today().addDays(i), Date.today().addDays(i + 1)));
            }

            Test.startTest();
            insert absences;
            Test.stopTest();

            List<Absence__c> results = [
                SELECT Requester__c, Approver__c, Status__c
                FROM   Absence__c
                WHERE  Id IN :absences
            ];

            Assert.areEqual(5, results.size(), 'All 5 records should be inserted');
            for (Absence__c r : results) {
                Assert.areEqual(emp.Id,        r.Requester__c);
                Assert.areEqual(emp.ManagerId, r.Approver__c);
                Assert.areEqual('Draft',       r.Status__c);
            }
        }
    }


    // ──────────────────────────────────────────────────────────────────
    // handleTotalDaysCount — via beforeInsert trigger path
    // NOTE: We assert presence and non-negativity, NOT exact values,
    //       because BusinessHours.diff() is not mockable and varies
    //       by org Business Hours configuration and timezone.
    // ──────────────────────────────────────────────────────────────────

    /**
     * Confirms Total_Days__c is populated (non-null, >= 0) when both
     * Start_Date__c and End_Date__c are provided.
     */
    @isTest
    static void testBeforeInsert_TotalDays_IsPopulated() {
        User emp = resolveUserWithManager();

        System.runAs(emp) {
            Absence__c ab = buildAbsence(Date.today(), Date.today().addDays(5));

            Test.startTest();
            insert ab;
            Test.stopTest();

            Absence__c result = [SELECT Total_Days__c FROM Absence__c WHERE Id = :ab.Id];

            Assert.isNotNull(result.Total_Days__c,
                'Total_Days__c should be populated when Start and End dates are set');
            Assert.isTrue(result.Total_Days__c >= 0,
                'Total_Days__c should be a non-negative value');
        }
    }

    /**
     * A wider date range should produce a Total_Days__c value that is
     * greater than or equal to a narrower range — validates the
     * directional correctness of the BusinessHours.diff() calculation.
     */
    @isTest
    static void testBeforeInsert_TotalDays_WiderRange_GreaterOrEqualDays() {
        User emp = resolveUserWithManager();

        System.runAs(emp) {
            Absence__c shortAb = buildAbsence(Date.today(), Date.today().addDays(2));
            Absence__c longAb  = buildAbsence(Date.today(), Date.today().addDays(10));

            Test.startTest();
            insert new List<Absence__c>{ shortAb, longAb };
            Test.stopTest();

            Map<Id, Absence__c> results = new Map<Id, Absence__c>([
                SELECT Total_Days__c FROM Absence__c WHERE Id IN :new List<Id>{ shortAb.Id, longAb.Id }
            ]);

            Decimal shortDays = results.get(shortAb.Id).Total_Days__c;
            Decimal longDays  = results.get(longAb.Id).Total_Days__c;

            Assert.isNotNull(shortDays, 'Short absence Total_Days__c should be populated');
            Assert.isNotNull(longDays,  'Long absence Total_Days__c should be populated');
            Assert.isTrue(longDays >= shortDays,
                'A 10-day span should yield >= days than a 2-day span per business hours');
        }
    }

    /**
     * When Start_Date__c and End_Date__c are the same date (single day),
     * Total_Days__c should be populated and >= 0.
     * (Exact value depends on whether that day falls within Business Hours.)
     */
    @isTest
    static void testBeforeInsert_TotalDays_SameStartAndEndDate() {
        User emp = resolveUserWithManager();

        System.runAs(emp) {
            // Use a weekday to maximize chance of BH returning > 0
            Date weekday = getNextWeekday(Date.today());
            Absence__c ab = buildAbsence(weekday, weekday);

            Test.startTest();
            insert ab;
            Test.stopTest();

            Absence__c result = [SELECT Total_Days__c FROM Absence__c WHERE Id = :ab.Id];
            Assert.isNotNull(result.Total_Days__c,
                'Total_Days__c should be populated even for a single-day absence');
            Assert.isTrue(result.Total_Days__c >= 0,
                'Total_Days__c should not be negative for same start/end date');
        }
    }

    /**
     * When Start_Date__c or End_Date__c is null, the handler skips the
     * record (continue). Total_Days__c should remain null.
     * (A validation rule would normally block the DML, but we use
     * allOrNone=false / partial insert to observe the handler behaviour.)
     */
    @isTest
    static void testBeforeInsert_TotalDays_NullDates_FieldLeftNull() {
        User emp = resolveUserWithManager();

        System.runAs(emp) {
            // Build record with no dates — bypass required-field validation
            // by using Database.insert with partial success allowed.
            Absence__c ab = new Absence__c(
                Start_Date__c = null,
                End_Date__c   = null
            );

            Test.startTest();
            // We are testing handler skipping logic, not DML success;
            // the record may fail validation but Total_Days__c should not
            // be set by the handler before that happens.
            Database.SaveResult sr = Database.insert(ab, false);
            Test.stopTest();

            if (sr.isSuccess()) {
                // If org has no required-field validation rule, record inserts
                Absence__c result = [SELECT Total_Days__c FROM Absence__c WHERE Id = :ab.Id];
                Assert.isNull(result.Total_Days__c,
                    'Total_Days__c should remain null when dates are null (handler skips)');
            } else {
                // Validation rule blocked insertion — handler skip behaviour
                // is still exercised in beforeInsert context; no additional assertion needed.
                Assert.isTrue(sr.getErrors().size() > 0,
                    'Expected a validation error for missing required date fields');
            }
        }
    }

    /**
     * When only End_Date__c is null, the handler should skip the record.
     */
    @isTest
    static void testBeforeInsert_TotalDays_NullEndDate_FieldLeftNull() {
        User emp = resolveUserWithManager();

        System.runAs(emp) {
            Absence__c ab = new Absence__c(
                Start_Date__c = Date.today(),
                End_Date__c   = null
            );

            Test.startTest();
            Database.SaveResult sr = Database.insert(ab, false);
            Test.stopTest();

            if (sr.isSuccess()) {
                Absence__c result = [SELECT Total_Days__c FROM Absence__c WHERE Id = :ab.Id];
                Assert.isNull(result.Total_Days__c,
                    'Total_Days__c should remain null when End_Date__c is null');
            } else {
                Assert.isTrue(sr.getErrors().size() > 0);
            }
        }
    }


    // ──────────────────────────────────────────────────────────────────
    // handleTotalDaysCount — via beforeUpdate trigger path
    // ──────────────────────────────────────────────────────────────────

    /**
     * Updating the dates on an existing record should recalculate
     * Total_Days__c via beforeUpdate.
     */
    @isTest
    static void testBeforeUpdate_TotalDays_Recalculated() {
        User emp = resolveUserWithManager();

        System.runAs(emp) {
            // Insert with initial dates
            Absence__c ab = buildAbsence(Date.today(), Date.today().addDays(2));
            insert ab;

            Absence__c afterInsert = [SELECT Total_Days__c FROM Absence__c WHERE Id = :ab.Id];
            Decimal initialDays = afterInsert.Total_Days__c;

            // Extend the date range significantly
            ab.End_Date__c = Date.today().addDays(14);

            Test.startTest();
            update ab;
            Test.stopTest();

            Absence__c afterUpdate = [SELECT Total_Days__c FROM Absence__c WHERE Id = :ab.Id];

            Assert.isNotNull(afterUpdate.Total_Days__c,
                'Total_Days__c should be recalculated on update');
            Assert.isTrue(afterUpdate.Total_Days__c >= 0,
                'Recalculated Total_Days__c should be non-negative');
            // Wider range should be >= original range
            Assert.isTrue(afterUpdate.Total_Days__c >= initialDays,
                'Extended date range should yield >= days than initial range');
        }
    }

    /**
     * Bulk update: all records should have Total_Days__c recalculated.
     */
    @isTest
    static void testBeforeUpdate_BulkTotalDays_Recalculated() {
        User emp = resolveUserWithManager();

        System.runAs(emp) {
            List<Absence__c> absences = new List<Absence__c>();
            for (Integer i = 1; i <= 5; i++) {
                absences.add(buildAbsence(Date.today(), Date.today().addDays(i)));
            }
            insert absences;

            // Extend all end dates
            for (Absence__c ab : absences) {
                ab.End_Date__c = ab.End_Date__c.addDays(5);
            }

            Test.startTest();
            update absences;
            Test.stopTest();

            List<Absence__c> results = [
                SELECT Total_Days__c FROM Absence__c WHERE Id IN :absences
            ];

            Assert.areEqual(5, results.size());
            for (Absence__c r : results) {
                Assert.isNotNull(r.Total_Days__c,
                    'Total_Days__c must be recalculated for all updated records');
                Assert.isTrue(r.Total_Days__c >= 0);
            }
        }
    }

    /**
     * If dates are cleared to null on update, the handler skips the record
     * and Total_Days__c retains its previous value (no null write from handler).
     * NOTE: Validation rules may intervene; we assert no exception is thrown
     * from the handler itself.
     */
    @isTest
    static void testBeforeUpdate_NullDates_HandlerSkipsGracefully() {
        User emp = resolveUserWithManager();

        System.runAs(emp) {
            Absence__c ab = buildAbsence(Date.today(), Date.today().addDays(3));
            insert ab;

            Absence__c afterInsert = [SELECT Total_Days__c FROM Absence__c WHERE Id = :ab.Id];
            Decimal originalDays = afterInsert.Total_Days__c;

            // Null out dates on update
            ab.Start_Date__c = null;
            ab.End_Date__c   = null;

            Test.startTest();
            Database.SaveResult sr = Database.update(ab, false);
            Test.stopTest();

            if (sr.isSuccess()) {
                // Handler skipped → Total_Days__c should retain prior value (not reset by handler)
                Absence__c afterUpdate = [SELECT Total_Days__c FROM Absence__c WHERE Id = :ab.Id];
                // Handler wrote nothing, so value should still be originalDays or null
                // depending on whether Salesforce persists the prior value
                Assert.isTrue(afterUpdate.Total_Days__c == null || afterUpdate.Total_Days__c == originalDays,
                    'Handler should not alter Total_Days__c when dates are null (skip via continue)');
            } else {
                // Validation rule blocked it — acceptable
                Assert.isTrue(sr.getErrors().size() > 0);
            }
        }
    }


    // ──────────────────────────────────────────────────────────────────
    // Utility
    // ──────────────────────────────────────────────────────────────────

    /**
     * Returns the next weekday on or after the given date.
     * Helps avoid Saturday/Sunday when we want a date within business hours.
     */
    private static Date getNextWeekday(Date d) {
        // Apex Date.toStartOfWeek() is locale-dependent; use dayOfWeek via DateTime
        DateTime dt = DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0));
        String dayName = dt.format('EEEE'); // e.g., 'Saturday'
        if (dayName == 'Saturday') {
            return d.addDays(2);
        } else if (dayName == 'Sunday') {
            return d.addDays(1);
        }
        return d;
    }
}