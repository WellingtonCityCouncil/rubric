var engine = null;
app.ports.askRubric.subscribe(function(data) {
  console.log(data);

  if (engine) {
    engine.process(data.answers).then(() => {
      console.log(engine.standards);
      app.ports.receiveSections.send(engine.standards);
    });
  } else {
    engine = new Rubric({ fields: data.scenario });
    app.ports.receiveSections.send(engine.standards);
  }
});
