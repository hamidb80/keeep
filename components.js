let components = [
  {
    name: "markdown",
    icon: "bi-md",
    data: {
      content: "string",
      text_dir: "string",
      text_align: "string",
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
      <div style="
        text-direction: {dir};
        text-align:     {align};
      ">
        {content|markdown2html}
      </div>
    `
  }
]