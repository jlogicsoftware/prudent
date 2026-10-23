package prudent.error;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.sql.SQLException;
import org.junit.jupiter.api.Test;

class ServerFailureReportTest {

  /** What Postgres really puts in the message of a NOT NULL violation. */
  private static final String ROW =
      "ERROR: null value in column \"category_id\" violates not-null constraint\n"
          + "  Detail: Failing row contains (7f3c, Salary, 12345.67, EUR).";

  @Test
  void neverContainsAnyExceptionMessage() {
    Throwable failure =
        new IllegalStateException("could not persist 12345.67", new SQLException(ROW, "23502"));

    String line = ServerFailureReport.describe("req-1", "POST", "RecordResource.create", 500, failure);

    assertFalse(line.contains("12345.67"), line);
    assertFalse(line.contains("Salary"), line);
    assertFalse(line.contains("\n"), line);
  }

  @Test
  void namesTheChainTheSqlStateAndTheRequest() {
    Throwable failure =
        new IllegalStateException("outer", new SQLException(ROW, "23502"));

    String line = ServerFailureReport.describe("req-1", "POST", "RecordResource.create", 500, failure);

    assertTrue(line.startsWith("request=req-1 method=POST handler=RecordResource.create status=500 "), line);
    assertTrue(
        line.contains("failure=java.lang.IllegalStateException <- java.sql.SQLException"), line);
    assertTrue(line.contains("sqlstate=23502"), line);
  }

  @Test
  void pointsAtTheFirstPrudentFrameOfTheRootCause() {
    Throwable failure = new RuntimeException("x");
    failure.setStackTrace(
        new StackTraceElement[] {
          new StackTraceElement("org.hibernate.Foo", "bar", "Foo.java", 1),
          new StackTraceElement("prudent.record.RecordResource", "create", "RecordResource.java", 88),
          new StackTraceElement("prudent.other.Other", "run", "Other.java", 3)
        });

    assertTrue(
        ServerFailureReport.describeFailure(failure)
            .endsWith("at=prudent.record.RecordResource.create(RecordResource.java:88)"));
  }

  @Test
  void fallsBackToTheFirstFrameWhenNoneIsPrudents() {
    Throwable failure = new RuntimeException("x");
    failure.setStackTrace(
        new StackTraceElement[] {new StackTraceElement("org.hibernate.Foo", "bar", "Foo.java", 1)});

    assertTrue(ServerFailureReport.describeFailure(failure).endsWith("at=org.hibernate.Foo.bar(Foo.java:1)"));
  }

  @Test
  void survivesACauseThatIsItself() {
    Throwable failure =
        new RuntimeException("x") {
          @Override
          public synchronized Throwable getCause() {
            return this;
          }
        };

    assertEquals(1, ServerFailureReport.describeFailure(failure).split(" <- ").length);
  }
}
