// /analysis — placeholder for the third PDF feature ("AI 디스커션 분석").
//
// Out of scope for this assignment but the route exists so the dynamic
// header tab maps cleanly: anyone with the `analysis` feature in their
// active membership sees this entry, and the `RequireAccess` guard at
// the route level handles the forbidden case.

export function AnalysisPage() {
  return (
    <div className="card">
      <h2>AI 분석</h2>
      <p className="muted">
        대화 기록 기반 레벨 분석 기능은 곧 제공될 예정이에요. 현재는
        대화 / 학습 탭을 사용해보세요.
      </p>
    </div>
  )
}
