// params: {
//   inline: "bool"
// },


let components = [
  {
    name: "markdown",
    aliases: ["md"],
    icon: "bi bi-md",
    states: {
      content: "string",
      dir: "string",
      align: "string",
    },
    settings: [
      {
        label: "content",
        icon: "bi-alphabet",
        mode: "multiline-text",
        sync: "content",
      },
      {
        label: "text-direction",
        icon: "bi-arrow",
        mode: ["auto", "ltr", "rtl"],
        sync: "dir",
      },
      {
        label: "text-align",
        icon: "bi-arrow",
        mode: ["auto", "left", "right", "center"],
        sync: "align",
      },
    ],
    template: `
      <div 
        style="
          text-direction: {dir};
          text-align:     {align};
      ">
        {content|markdown2html}
      </div>
    `
  }
]
