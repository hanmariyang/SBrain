import SwiftUI

// MARK: - Database Browser (Left Panel — table list sidebar)

struct DatabaseBrowserView: View {
    @EnvironmentObject var dbStore: DatabaseStore

    var body: some View {
        if !dbStore.isConnected {
            DBConnectionView()
        } else {
            DBTableListView()
        }
    }
}

// MARK: - Connection View

private struct DBConnectionView: View {
    @EnvironmentObject var dbStore: DatabaseStore
    @State private var urlInput: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 56))
                .foregroundStyle(
                    .linearGradient(
                        colors: [SB.Colors.accentGreen, SB.Colors.accentBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.5)

            Text("PostgreSQL 데이터베이스 연결")
                .font(.title3)
                .foregroundStyle(SB.Colors.navy500)

            Text("읽기 전용으로 테이블 구조와 데이터를 탐색합니다")
                .font(.caption)
                .foregroundStyle(SB.Colors.navy300)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundStyle(SB.Colors.accentGreen)
                        .font(.system(size: 12))

                    TextField("postgres://user:pass@host:5432/dbname", text: $urlInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(SB.Colors.navy900)
                        .onSubmit { connect() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(SB.Colors.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.green.opacity(0.2), lineWidth: 1)
                )

                Button(action: connect) {
                    HStack(spacing: 6) {
                        if dbStore.isConnecting {
                            ProgressView().scaleEffect(0.6).tint(.white)
                        }
                        Text(dbStore.isConnecting ? "연결 중..." : "연결")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [SB.Colors.accentGreen.opacity(0.5), SB.Colors.accentBlue.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)  // 버튼 위 흰색 텍스트 (green gradient bg)
                .disabled(dbStore.isConnecting || urlInput.trimmingCharacters(in: .whitespaces).isEmpty)

                if let error = dbStore.connectionError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.7))
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: 480)

            Spacer()
        }
        .onAppear { urlInput = dbStore.connectionURL }
    }

    private func connect() {
        dbStore.connectionURL = urlInput
        Task { await dbStore.connect() }
    }
}

// MARK: - Table List Sidebar

private struct DBTableListView: View {
    @EnvironmentObject var dbStore: DatabaseStore

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 11))
                    .foregroundStyle(.green.opacity(0.7))

                Text(dbStore.databaseName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SB.Colors.navy900)
                    .lineLimit(1)

                Spacer()

                Button(action: { dbStore.disconnect() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(SB.Colors.navy300)
                }
                .buttonStyle(.plain)
                .help("연결 해제")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.06))

            // Schema picker
            if dbStore.schemas.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(dbStore.schemas) { schema in
                            let isActive = dbStore.selectedSchema == schema.name
                            Button(action: {
                                Task { await dbStore.selectSchema(schema.name) }
                            }) {
                                HStack(spacing: 4) {
                                    Text(schema.name)
                                        .font(.system(size: 10, weight: isActive ? .bold : .regular, design: .monospaced))
                                        .foregroundStyle(isActive ? SB.Colors.navy900 : SB.Colors.navy500)
                                    Text("\(schema.tableCount)")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(SB.Colors.navy300)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isActive ? SB.Colors.accentGreen.opacity(0.15) : SB.Colors.bgTertiary.opacity(0.5))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .background(SB.Colors.bgTertiary)
            }

            Divider().background(SB.Colors.navy100)

            // Table list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(dbStore.tables) { table in
                        DBTableRow(table: table, isSelected: dbStore.selectedTable?.id == table.id)
                            .onTapGesture {
                                Task { await dbStore.selectTable(table) }
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(SB.Colors.bgSecondary)
    }
}

private struct DBTableRow: View {
    let table: DBTable
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: table.type == "VIEW" ? "eye" : "tablecells")
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? SB.Colors.accentGreen : SB.Colors.navy300)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(table.name)
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(isSelected ? SB.Colors.navy900 : SB.Colors.navy700)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(table.columnCount) cols")
                    Text("~\(formatRowCount(table.rowEstimate)) rows")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SB.Colors.navy300)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.green.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    private func formatRowCount(_ count: Int) -> String {
        if count >= 1_000_000 { return "\(count / 1_000_000)M" }
        if count >= 1_000 { return "\(count / 1_000)K" }
        return "\(count)"
    }
}

// MARK: - Database Detail View (Right Panel — viewer area)

struct DBDetailView: View {
    @EnvironmentObject var dbStore: DatabaseStore

    var body: some View {
        ZStack {
            SB.Colors.bgPrimary

            VStack(spacing: 0) {
                // DB search bar
                if dbStore.isConnected {
                    dbSearchBar
                }

                // Search results
                if !dbStore.searchResults.isEmpty {
                    dbSearchResults
                }

                if let row = dbStore.selectedRow {
                    // Row detail mode
                    rowDetailView(columns: row.columns, values: row.values)
                } else if let table = dbStore.selectedTable {
                    // Table detail + data grid
                    tableDetailView(table)
                } else if dbStore.isConnected {
                    // Connected but no table selected
                    dbOverview
                } else {
                    emptyState
                }
            }
        }
    }

    // MARK: - Search Bar

    private var dbSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(dbStore.searchResults.isEmpty ? SB.Colors.accentGreen : .yellow.opacity(0.8))
                .font(.system(size: 12))

            TextField("DB 회상하기...", text: $dbStore.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(SB.Colors.navy900)
                .onSubmit { Task { await dbStore.searchDB() } }

            if !dbStore.searchResults.isEmpty {
                Text("\(dbStore.searchResults.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.15))
                    .clipShape(Capsule())
            }

            if !dbStore.searchQuery.isEmpty {
                Button(action: { dbStore.clearSearch() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SB.Colors.navy300)
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }

            if dbStore.isSearching {
                ProgressView().scaleEffect(0.5).tint(.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(SB.Colors.bgSecondary)
    }

    // MARK: - Search Results

    private var dbSearchResults: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DB 회상 결과 \(dbStore.searchResults.count)건")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.yellow.opacity(0.9))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.yellow.opacity(0.06))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(dbStore.searchResults) { result in
                        Button(action: {
                            // Navigate to the table
                            Task {
                                if dbStore.selectedSchema != result.schema {
                                    await dbStore.selectSchema(result.schema)
                                }
                                if let table = dbStore.tables.first(where: { $0.name == result.table }) {
                                    await dbStore.selectTable(table)
                                }
                            }
                        }) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text("\(result.schema).\(result.table)")
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.green.opacity(0.8))
                                        Text(result.column)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(SB.Colors.navy500)
                                    }
                                    Text(result.value)
                                        .font(.system(size: 11))
                                        .foregroundStyle(SB.Colors.navy700)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(SB.Colors.bgSecondary.opacity(0.3))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 200)

            Divider().background(.yellow.opacity(0.15))
        }
    }

    // MARK: - DB Overview

    private var dbOverview: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 40))
                .foregroundStyle(.green.opacity(0.3))

            if let info = dbStore.connectionInfo {
                Text(info.database ?? "Database")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(SB.Colors.navy500)

                HStack(spacing: 16) {
                    statBadge(label: "스키마", value: "\(dbStore.schemas.count)")
                    statBadge(label: "테이블", value: "\(dbStore.tables.count)")
                }
            }

            Text("왼쪽에서 테이블을 선택하세요")
                .font(.system(size: 12))
                .foregroundStyle(SB.Colors.navy300)

            Spacer()
        }
    }

    private func statBadge(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(.green.opacity(0.7))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(SB.Colors.navy300)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 40))
                .foregroundStyle(SB.Colors.navy100)
            Text("데이터베이스에 연결하면 여기에 테이블 정보가 표시됩니다")
                .font(.system(size: 13))
                .foregroundStyle(SB.Colors.navy300)
        }
    }

    // MARK: - Table Detail + Data Grid

    private func tableDetailView(_ table: DBTable) -> some View {
        VStack(spacing: 0) {
            // Table header
            HStack(spacing: 8) {
                Image(systemName: "tablecells")
                    .font(.system(size: 13))
                    .foregroundStyle(.green.opacity(0.7))

                Text("\(table.schema).\(table.name)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(SB.Colors.navy900)

                if table.type == "VIEW" {
                    Text("VIEW")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(SB.Colors.accentBlue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(SB.Colors.accentBlue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                Text("\(dbStore.columns.count) columns")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SB.Colors.navy300)

                Text("~\(formatRowCount(table.rowEstimate)) rows")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SB.Colors.navy300)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // Gradient divider
            Rectangle()
                .fill(LinearGradient(
                    colors: [SB.Colors.accentGreen.opacity(0.4), SB.Colors.gold600.opacity(0.4), .clear],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 1)

            // Column schema strip
            if !dbStore.columns.isEmpty {
                schemaStrip
            }

            // Data grid
            if dbStore.isLoadingRows {
                Spacer()
                ProgressView().tint(.green)
                Text("데이터 로드 중...")
                    .font(.system(size: 11))
                    .foregroundStyle(SB.Colors.navy300)
                Spacer()
            } else if let response = dbStore.rows {
                dataTable(response)
                paginationBar(response)
            }
        }
    }

    private var schemaStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(dbStore.columns) { col in
                    HStack(spacing: 3) {
                        Text(col.name)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(SB.Colors.navy500)
                        Text(col.type)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.5))
                        if col.nullable {
                            Text("?")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.yellow.opacity(0.4))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(SB.Colors.bgTertiary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(SB.Colors.bgTertiary)
    }

    // MARK: - Data Table

    private func dataTable(_ response: DBRowsResponse) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                // Column headers (pinned — outside vertical scroll)
                HStack(spacing: 0) {
                    Text("#")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(SB.Colors.navy300)
                        .frame(width: 40, alignment: .center)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.08))

                    ForEach(response.columns, id: \.self) { col in
                        Text(col)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SB.Colors.navy900)
                            .frame(minWidth: 100, maxWidth: 200, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.08))
                    }
                }

                Divider().background(.green.opacity(0.3))

                // Data rows (vertically scrollable)
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(response.rows.enumerated()), id: \.offset) { rowIdx, row in
                            let isRowSelected = dbStore.selectedRowIndex == rowIdx
                            HStack(spacing: 0) {
                                Text("\(response.offset + rowIdx + 1)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(SB.Colors.navy300)
                                    .frame(width: 40, alignment: .center)
                                    .padding(.vertical, 5)

                                ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                    Text(value.description)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(cellColor(value))
                                        .lineLimit(1)
                                        .frame(minWidth: 100, maxWidth: 200, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                }
                            }
                            .background(isRowSelected ? SB.Colors.accentGreen.opacity(0.1) : (rowIdx % 2 == 0 ? Color.clear : SB.Colors.bgSecondary.opacity(0.2)))
                            .overlay(isRowSelected ? RoundedRectangle(cornerRadius: 0).stroke(Color.green.opacity(0.4), lineWidth: 1) : nil)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dbStore.selectRow(isRowSelected ? nil : rowIdx)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cellColor(_ value: JSONValue) -> Color {
        switch value {
        case .null: return SB.Colors.navy300
        case .int, .double: return SB.Colors.accentBlue
        case .bool: return SB.Colors.gold600
        case .string: return SB.Colors.navy700
        }
    }

    private func paginationBar(_ response: DBRowsResponse) -> some View {
        HStack(spacing: 12) {
            Text("~\(response.totalEstimate) rows")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SB.Colors.navy300)

            Spacer()

            Button(action: {
                dbStore.selectRow(nil)
                Task { await dbStore.loadPage(dbStore.currentPage - 1) }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(dbStore.currentPage > 0 ? SB.Colors.navy700 : SB.Colors.navy300)
            .disabled(dbStore.currentPage <= 0)

            Text("\(dbStore.currentPage + 1) / \(dbStore.totalPages)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SB.Colors.navy500)

            Button(action: {
                dbStore.selectRow(nil)
                Task { await dbStore.loadPage(dbStore.currentPage + 1) }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(dbStore.currentPage + 1 < dbStore.totalPages ? SB.Colors.navy700 : SB.Colors.navy300)
            .disabled(dbStore.currentPage + 1 >= dbStore.totalPages)

            Text("(\(response.offset + 1)–\(response.offset + response.rows.count))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SB.Colors.navy300)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(SB.Colors.bgSecondary)
    }

    // MARK: - Row Detail View

    private func rowDetailView(columns: [String], values: [JSONValue]) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { dbStore.selectRow(nil) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text("테이블로 돌아가기")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.green.opacity(0.7))
                }
                .buttonStyle(.plain)

                Spacer()

                if let table = dbStore.selectedTable {
                    Text("\(table.schema).\(table.name)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SB.Colors.navy500)
                }

                if let idx = dbStore.selectedRowIndex, let rows = dbStore.rows {
                    Text("Row #\(rows.offset + idx + 1)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(SB.Colors.bgSecondary)

            Rectangle()
                .fill(LinearGradient(
                    colors: [SB.Colors.accentGreen.opacity(0.4), SB.Colors.gold600.opacity(0.4), .clear],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 1)

            // Row fields
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(zip(columns, values).enumerated()), id: \.offset) { idx, pair in
                        let (colName, value) = pair
                        let colInfo = dbStore.columns.first(where: { $0.name == colName })

                        HStack(alignment: .top, spacing: 12) {
                            // Column name + type
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(colName)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.green.opacity(0.8))
                                if let info = colInfo {
                                    Text(info.type)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(SB.Colors.navy300)
                                }
                            }
                            .frame(width: 130, alignment: .trailing)

                            // Value
                            Text(value.description)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(cellColor(value))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(idx % 2 == 0 ? Color.clear : SB.Colors.bgSecondary.opacity(0.3))
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func formatRowCount(_ count: Int) -> String {
        if count >= 1_000_000 { return "\(count / 1_000_000)M" }
        if count >= 1_000 { return "\(count / 1_000)K" }
        return "\(count)"
    }
}
