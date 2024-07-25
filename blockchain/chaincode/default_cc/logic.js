"use strict";
const { Contract } = require("fabric-contract-api");

class testContract extends Contract {
  async Init(stub) {
    console.log("inside Init");
  }

  async Invoke(stub) {
    console.log("inside Invoke");
  }

  // can be removed in case we find a way to have optional parameters
  // see: https://stackoverflow.com/questions/68858960
  async getAllMarks(ctx, studentId) {
    return await this.getMarks(ctx, studentId, null);
  }

  async getAllAvgMarks(ctx, studentId) {
    return await this.getAvgMarks(ctx, studentId, null);
  }

  async getMarks(ctx, studentId, subject) {
    let marksAsBytes = await ctx.stub.getState(studentId);
    console.debug("Querying the ledger for studentId: %s", studentId);
    if (!marksAsBytes || marksAsBytes.toString().length <= 0) {
      throw new Error("Student Id not found: %s", studentId);
    }
    let marks = JSON.parse(marksAsBytes.toString());
    if (subject != null) {
      if (marks[subject] == null) {
        throw new Error(
          "Student %s has no resgistered marks for subject %s",
          studentId,
          subject
        );
      }
      marks = { [subject]: marks[subject] };
    }
    return JSON.stringify(marks);
  }

  async getAvgMarks(ctx, studentId, subject) {
    let marks = JSON.parse(await this.getAllMarks(ctx, studentId, subject));
    console.trace("Calculating average values, round to the 2nd decimal place");
    let avgs = {};
    for (let subject in marks) {
      let sum = 0;
      marks[subject].forEach((t) => {
        sum += Number(t);
      });
      let avg = sum / marks[subject].length;
      avgs[subject] = parseFloat(avg.toFixed(2));
    }
    return JSON.stringify(avgs);
  }

  async addMark(ctx, studentId, subject, mark) {
    let marks = {};
    let marksAsBytes = await ctx.stub.getState(studentId);
    if (!marksAsBytes || marksAsBytes.toString().length <= 0) {
      console.warn("No entry found for %o, creating new one", { studentId });
    } else {
      marks = JSON.parse(marksAsBytes.toString());
    }
    if (marks[subject] == null) {
      console.warn("No entry found for %o, creating new one", {
        studentId,
        subject,
      });
      marks[subject] = [];
    } else {
      console.debug("existing marks", marks[subject]);
    }
    let list = marks[subject];
    console.debug("logging data ", subject, marks[subject], list);
    let index = list.push(mark);
    console.debug("logging data ", subject, marks[subject], list);
    marks[subject] = list;
    console.debug("logging data ", subject, marks[subject], list);

    await ctx.stub.putState(studentId, Buffer.from(JSON.stringify(marks)));

    console.log("Added new mark to the ledger: %o", {
      studentId,
      subject,
      mark,
      index,
    });
  }

  async deleteMarks(ctx, studentId) {
    await ctx.stub.deleteState(studentId);

    console.log(
      "Marks belonging to student %s were deleted from the ledger",
      studentId
    );
  }
}

module.exports = testContract;
